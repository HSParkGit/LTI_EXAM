# frozen_string_literal: true

# 출결 세션 자동 동기화 서비스
#
# Canvas Module Items와 AttendanceSession을 자동으로 동기화
# 멱등성 보장: 몇 번을 실행해도 결과가 동일
#
# 동기화 규칙:
# | Canvas 상태 | 우리 세션   | 동작        |
# |-------------|-------------|-------------|
# | 있음        | 없음        | 생성        |
# | 있음        | active      | 스킵        |
# | 있음        | deleted     | 복원        |
# | 없음        | active      | soft delete |
# | 없음        | deleted     | 스킵        |
#
class AttendanceSyncService
  attr_reader :result

  def initialize(lti_context:, canvas_api:)
    @lti_context = lti_context
    @canvas_api = canvas_api
    @result = { created: 0, restored: 0, soft_deleted: 0, skipped: 0 }
  end

  def sync!
    return @result unless @canvas_api
    return @result unless @lti_context.sync_needed?

    canvas_items = fetch_canvas_items
    perform_sync(canvas_items)
    @lti_context.update!(last_synced_at: Time.current)
    @result
  rescue => e
    Rails.logger.error "AttendanceSyncService 실패: #{e.class} - #{e.message}"
    @result
  end

  private

  def fetch_canvas_items
    course_id = @lti_context.canvas_course_id
    return [] unless course_id.present?

    modules_client = CanvasApi::ModulesClient.new(@canvas_api)
    all_items = modules_client.list_all_module_items(course_id)

    # Panopto(VOD) 또는 Zoom(LIVE)만 필터
    all_items.select do |item|
      url = item['external_url'].to_s.downcase
      (item['type'] == 'ExternalTool' && url.include?('panopto')) ||
        (item['type'] == 'ExternalUrl' && url.include?('zoom'))
    end
  end

  def perform_sync(canvas_items)
    canvas_tag_ids = canvas_items.map { |i| i['id'] }.compact.to_set

    # soft delete 포함 전체 세션 조회 (content_tag_id가 있는 것만)
    all_sessions = @lti_context.attendance_sessions
                               .where.not(content_tag_id: nil)
    existing_by_tag = all_sessions.index_by(&:content_tag_id)

    ActiveRecord::Base.transaction do
      # Canvas에 있는 아이템 처리: CREATE 또는 RESTORE
      canvas_items.each do |item|
        tag_id = item['id']
        session = existing_by_tag[tag_id]

        if session.nil?
          create_session_from_item(item)
          @result[:created] += 1
        elsif session.deleted?
          session.restore!
          @result[:restored] += 1
        else
          @result[:skipped] += 1
        end
      end

      # Canvas에 없는 active 세션: SOFT DELETE
      active_sessions_not_in_canvas = @lti_context.attendance_sessions
                                                   .active
                                                   .where.not(content_tag_id: nil)
      if canvas_tag_ids.any?
        active_sessions_not_in_canvas = active_sessions_not_in_canvas
                                          .where.not(content_tag_id: canvas_tag_ids.to_a)
      end

      active_sessions_not_in_canvas.find_each do |session|
        session.soft_delete!
        @result[:soft_deleted] += 1
      end
    end
  end

  def create_session_from_item(item)
    attendance_type = determine_type(item)
    week = [item['module_position'].to_i, 1].max
    lesson_id = [item['position'].to_i, 1].max

    # 주차/차시 중복 방지 (active 세션 기준)
    while @lti_context.attendance_sessions.active.exists?(week: week, lesson_id: lesson_id)
      lesson_id += 1
    end

    session = @lti_context.attendance_sessions.build(
      week: week,
      lesson_id: lesson_id,
      title: item['title'],
      attendance_type: attendance_type,
      content_tag_id: item['id']
    )

    if attendance_type == 'vod'
      build_default_vod_setting(session, item)
    else
      build_default_live_setting(session)
    end

    unless session.save
      Rails.logger.error "세션 생성 실패 (#{item['title']}): #{session.errors.full_messages.join(', ')}"
      @result[:created] -= 1
    end
  end

  def determine_type(item)
    item['type'] == 'ExternalTool' && item['external_url'].to_s.downcase.include?('panopto') ? 'vod' : 'live'
  end

  def build_default_vod_setting(session, item)
    unlock_at = if item['module_unlock_at'].present?
                  Time.zone.parse(item['module_unlock_at'])
                else
                  Time.current
                end

    session.build_vod_setting(
      allow_attendance: true,
      allow_tardiness: true,
      percent_required: 80,
      unlock_at: unlock_at,
      attendance_finish_at: unlock_at + 7.days,
      tardiness_finish_at: unlock_at + 14.days
    )
  end

  def build_default_live_setting(session)
    session.build_live_setting(
      allow_attendance: true,
      allow_tardiness: true,
      attendance_threshold: 80,
      tardiness_threshold: 50
    )
  end
end
