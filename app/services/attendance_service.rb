# frozen_string_literal: true

#
# 출결 서비스 (재작성)
# Canvas 원본 로직 기반
#
# 핵심 기능:
# - 세션 목록 조회 + 통계
# - 세션별 학생 출결 리스트
# - 학생별 전체 출결 현황
# - Canvas Module Item 연동
#
class AttendanceService
  class AttendanceServiceError < StandardError; end

  def initialize(lti_context:, lti_claims:, canvas_api: nil)
    @lti_context = lti_context
    @lti_claims = lti_claims
    @canvas_api = canvas_api

    @user_sub = lti_claims[:user_sub] || lti_claims['user_sub']
    user_role = lti_claims[:user_role] || lti_claims['user_role']
    @is_instructor = %w[instructor teacher administrator].include?(user_role.to_s.downcase)
  end

  # ========================================
  # 세션 목록 + 통계 (주차별 그룹핑)
  # ========================================

  # @return [Hash] { sessions_by_week: {...}, stats: {...}, total_sessions: N }
  def sessions_with_statistics
    sessions = @lti_context.attendance_sessions.active
                           .includes(:vod_setting, :live_setting)
                           .ordered

    return empty_sessions_result if sessions.blank?

    # 외부 데이터 일괄 조회
    records = AttendanceQueryHelper.fetch_records_for_sessions(sessions)
    records_index = AttendanceQueryHelper.index_records(records)

    # 학생인 경우: 본인 식별자 맵 구축
    identifiers_map = unless @is_instructor
                        AttendanceQueryHelper.build_identifiers_map(@lti_claims, sessions)
                      end

    # 주차별 그룹핑
    sessions_by_week = sessions.group_by(&:week).transform_values do |week_sessions|
      week_sessions.map do |session|
        data = build_session_data(session, records_index)

        # 학생인 경우: 본인 출결 레코드 추가
        unless @is_instructor
          identifier = identifiers_map&.dig(session.id)
          my_record = if identifier && session.content_tag_id
                        AttendanceQueryHelper.find_record(identifier, records_index, session.content_tag_id)
                      end
          data[:my_record] = my_record
          data[:my_status] = if my_record
                               AttendanceStatsCalculator.convert_state_to_string(my_record.attendance_state, session: session)
                             else
                               AttendanceStatsCalculator.resolve_pending_status(session)
                             end
        end

        data
      end
    end

    # 전체 통계 (간단한 합산)
    all_stats = sessions_by_week.values.flatten.map { |s| s[:stats] }
    total_stats = merge_stats(all_stats)

    {
      sessions_by_week: sessions_by_week,
      stats: total_stats,
      total_sessions: sessions.count
    }
  end

  # ========================================
  # 세션별 학생 출결 리스트 (교수용)
  # ========================================

  # @param session [AttendanceSession]
  # @return [Array] 학생별 출결 기록
  def session_students(session)
    return [] unless session.content_tag_id.present?

    records = session.view_results.to_a
    records_by_id = build_records_by_student_id(records)

    # Canvas API로 전체 수강생 목록 조회
    enrolled = fetch_enrolled_students
    if enrolled.present?
      build_students_from_enrolled(session, enrolled, records_by_id)
    else
      # Canvas API 없으면 레코드 있는 학생만 (폴백)
      build_students_from_records(session, records)
    end
  end

  # 세션 통계 (교수용)
  # @param session [AttendanceSession]
  # @return [Hash] 출결 통계
  def session_stats(session)
    return empty_stats unless session.content_tag_id.present?

    records = session.view_results.to_a
    enrolled = fetch_enrolled_students
    total_students = enrolled.present? ? enrolled.count : records.count

    AttendanceStatsCalculator.calculate_stats(session, records, total_students)
  end

  # ========================================
  # 학생 본인의 출결 (학생용)
  # ========================================

  # 특정 세션의 본인 출결
  # @param session [AttendanceSession]
  # @return [Hash, nil] 출결 정보
  def my_session_record(session)
    identifier = AttendanceQueryHelper.extract_student_identifier(@lti_claims, session)
    return nil unless identifier && session.content_tag_id

    record = session.find_student_result(identifier)
    return nil unless record

    {
      record: record,
      status: AttendanceStatsCalculator.convert_state_to_string(record.attendance_state, session: session),
      status_label: record.attendance_state_text,
      teacher_forced: record.teacher_forced?
    }
  end

  # ========================================
  # 학생별 전체 출결 현황
  # ========================================

  # @param target_identifier [String, nil] 특정 학생 식별자 (nil이면 본인)
  # @return [Hash] { by_week: {...}, stats: {...}, user_name: '...' }
  def student_attendance(target_identifier = nil)
    sessions = @lti_context.attendance_sessions.active
                           .includes(:vod_setting, :live_setting)
                           .ordered

    return empty_student_result if sessions.blank?

    # 본인 또는 특정 학생의 식별자 결정
    if target_identifier.blank?
      identifiers_map = AttendanceQueryHelper.build_identifiers_map(@lti_claims, sessions)
    end

    # 외부 데이터 조회
    records = AttendanceQueryHelper.fetch_records_for_sessions(sessions)
    records_index = AttendanceQueryHelper.index_records(records)

    # 주차별 출결 데이터 구성
    by_week = {}
    stats = { present: 0, excused: 0, late: 0, absent: 0, pending: 0 }
    user_name = nil

    sessions.each do |session|
      next unless session.content_tag_id

      identifier = if target_identifier.present?
                     target_identifier
                   else
                     identifiers_map[session.id]
                   end
      next unless identifier

      record = AttendanceQueryHelper.find_record(identifier, records_index, session.content_tag_id)
      status = if record
                 AttendanceStatsCalculator.convert_state_to_string(record.attendance_state, session: session)
               else
                 AttendanceStatsCalculator.resolve_pending_status(session)
               end

      # 통계 업데이트
      case status
      when 'present' then stats[:present] += 1
      when 'excused' then stats[:excused] += 1
      when 'late' then stats[:late] += 1
      when 'absent' then stats[:absent] += 1
      else stats[:pending] += 1
      end

      # 사용자 이름 캐시
      if user_name.nil? && record
        user_name = record.respond_to?(:user_name) ? record.user_name : record.user_email
      end

      # 주차별 그룹핑
      week = session.week
      by_week[week] ||= []
      by_week[week] << {
        session: session,
        record: record,
        status: status,
        status_label: record&.attendance_state_text || status_label(status)
      }
    end

    {
      by_week: by_week,
      stats: stats,
      user_name: user_name,
      user_identifier: target_identifier || identifiers_map&.values&.first
    }
  end

  # ========================================
  # 학생×세션 매트릭스 (교수용)
  # ========================================

  # @return [Hash] { students: [...], sessions_by_week: {...} }
  def student_lectures_matrix
    sessions = @lti_context.attendance_sessions.active
                           .includes(:vod_setting, :live_setting)
                           .where.not(content_tag_id: nil)
                           .ordered

    enrolled = fetch_enrolled_students
    return { students: [], lesson_slots_by_week: {} } if sessions.blank? || enrolled.blank?

    # 외부 데이터 일괄 조회 + 인덱싱
    records = AttendanceQueryHelper.fetch_records_for_sessions(sessions)
    records_index = AttendanceQueryHelper.index_records(records)

    # [week, lesson_id] 단위로 그룹핑 → lesson_slot
    # 같은 week+lesson에 여러 세션(콘텐츠)이 있을 수 있음
    lesson_slots = sessions.group_by { |s| [s.week, s.lesson_id] }.sort.to_h
    lesson_slots_by_week = {}
    lesson_slots.each do |(week, lesson_id), slot_sessions|
      lesson_slots_by_week[week] ||= []
      lesson_slots_by_week[week] << {
        week: week,
        lesson_id: lesson_id,
        sessions: slot_sessions
      }
    end

    # 학생별 매트릭스 데이터 구축
    students = enrolled.map do |student|
      stats = { present: 0, excused: 0, late: 0, absent: 0, pending: 0 }
      slot_statuses = {}

      lesson_slots.each do |(week, lesson_id), slot_sessions|
        slot_key = "#{week}-#{lesson_id}"
        items = []

        slot_sessions.each do |session|
          identifier = session.vod? ? student[:login_id] : student[:email]
          record = identifier.present? ? AttendanceQueryHelper.find_record(identifier, records_index, session.content_tag_id) : nil

          status = if record
                     AttendanceStatsCalculator.convert_state_to_string(record.attendance_state, session: session)
                   else
                     AttendanceStatsCalculator.resolve_pending_status(session)
                   end

          items << {
            session_id: session.id,
            title: session.title.presence || session.week_lesson_label,
            type: session.attendance_type,
            status: status,
            identifier: identifier
          }
        end

        # 우선순위 기반 대표 상태: absent > late > present/excused > pending
        item_statuses = items.map { |i| i[:status] }
        priority_status = AttendanceStatsCalculator.determine_priority_status(item_statuses)

        case priority_status
        when 'present' then stats[:present] += 1
        when 'excused' then stats[:excused] += 1
        when 'late' then stats[:late] += 1
        when 'absent' then stats[:absent] += 1
        else stats[:pending] += 1
        end

        slot_statuses[slot_key] = {
          status: priority_status,
          items: items
        }
      end

      {
        user_id: student[:user_id],
        name: student[:name],
        login_id: student[:login_id],
        email: student[:email],
        stats: stats,
        slot_statuses: slot_statuses
      }
    end.sort_by { |s| s[:name].to_s }

    { students: students, lesson_slots_by_week: lesson_slots_by_week }
  end

  # ========================================
  # Canvas Module Items 연동
  # ========================================

  def unmapped_panopto_items
    items = fetch_items(:panopto)
    filter_unmapped(items)
  end

  def unmapped_zoom_items
    items = fetch_items(:zoom)
    filter_unmapped(items)
  end

  # ========================================
  # 일괄 생성
  # ========================================

  def unmapped_items_for_bulk
    return { modules: [] } unless @canvas_api

    course_id = @lti_context.canvas_course_id
    return { modules: [] } unless course_id.present?

    modules_client = CanvasApi::ModulesClient.new(@canvas_api)
    all_items = modules_client.list_all_module_items(course_id)
    mapped_ids = @lti_context.attendance_sessions.pluck(:content_tag_id).compact

    # Panopto/Zoom만 필터 + 이미 매핑된 것 제외
    unmapped = all_items.select do |item|
      url = item['external_url'].to_s.downcase
      (item['type'] == 'ExternalTool' && url.include?('panopto')) ||
        (item['type'] == 'ExternalUrl' && url.include?('zoom'))
    end.reject { |item| mapped_ids.include?(item['id']) }

    # Module별 그룹핑
    modules = unmapped.group_by { |item| item['module_name'] }
                      .sort_by { |_, items| items.first['module_position'] || 0 }
                      .map do |name, items|
      {
        name: name,
        position: items.first['module_position'],
        unlock_at: items.first['module_unlock_at'],
        items: items.sort_by { |i| i['position'] || 0 }
      }
    end

    { modules: modules }
  rescue => e
    Rails.logger.error "Canvas Module Items 조회 실패 (bulk): #{e.class} - #{e.message}"
    { modules: [] }
  end

  def bulk_create_sessions(selected_item_ids, items_data, common_settings)
    created = 0
    skipped = 0
    errors = []

    existing_ids = @lti_context.attendance_sessions
                               .where(content_tag_id: selected_item_ids)
                               .pluck(:content_tag_id)

    ActiveRecord::Base.transaction do
      selected_item_ids.each do |content_tag_id|
        if existing_ids.include?(content_tag_id)
          skipped += 1
          next
        end

        item = items_data.find { |i| i['id'].to_i == content_tag_id.to_i }
        next unless item

        attendance_type = determine_type(item)
        week = [item['module_position'].to_i, 1].max
        lesson_id = [item['position'].to_i, 1].max

        # 주차/차시 중복 방지
        while @lti_context.attendance_sessions.exists?(week: week, lesson_id: lesson_id)
          lesson_id += 1
        end

        session = @lti_context.attendance_sessions.build(
          week: week, lesson_id: lesson_id,
          title: item['title'],
          attendance_type: attendance_type,
          content_tag_id: content_tag_id
        )

        if attendance_type == 'vod'
          build_bulk_vod_setting(session, item, common_settings)
        else
          build_bulk_live_setting(session, common_settings)
        end

        if session.save
          created += 1
        else
          errors << { title: item['title'], messages: session.errors.full_messages }
        end
      end
    end

    { created: created, skipped: skipped, errors: errors }
  end

  private

  def fetch_items(type)
    return [] unless @canvas_api

    course_id = @lti_context.canvas_course_id
    return [] unless course_id.present?

    modules_client = CanvasApi::ModulesClient.new(@canvas_api)
    type == :panopto ? modules_client.list_panopto_items(course_id) : modules_client.list_zoom_items(course_id)
  rescue => e
    Rails.logger.error "Canvas Module Items 조회 실패: #{e.class} - #{e.message}"
    []
  end

  def filter_unmapped(items)
    mapped_ids = @lti_context.attendance_sessions.pluck(:content_tag_id).compact
    items.reject { |item| mapped_ids.include?(item['id']) }
  end

  def determine_type(item)
    item['type'] == 'ExternalTool' && item['external_url'].to_s.downcase.include?('panopto') ? 'vod' : 'live'
  end

  def build_bulk_vod_setting(session, item, settings)
    unlock_at = if item['module_unlock_at'].present?
                  Time.zone.parse(item['module_unlock_at'])
                else
                  Time.current
                end

    att_days = settings[:attendance_deadline_days].to_i
    tard_days = settings[:tardiness_deadline_days].to_i

    session.build_vod_setting(
      allow_attendance: true,
      allow_tardiness: tard_days > 0,
      percent_required: settings[:percent_required].present? ? settings[:percent_required].to_i : 80,
      unlock_at: unlock_at,
      attendance_finish_at: att_days > 0 ? unlock_at + att_days.days : nil,
      tardiness_finish_at: tard_days > 0 ? unlock_at + tard_days.days : nil
    )
  end

  def build_bulk_live_setting(session, settings)
    session.build_live_setting(
      allow_attendance: true,
      allow_tardiness: settings[:tardiness_threshold].present? && settings[:tardiness_threshold].to_i > 0,
      attendance_threshold: settings[:attendance_threshold].present? ? settings[:attendance_threshold].to_i : 80,
      tardiness_threshold: settings[:tardiness_threshold].present? ? settings[:tardiness_threshold].to_i : nil
    )
  end

  def build_session_data(session, records_index)
    # 이 세션의 레코드만 필터링
    session_records = if session.content_tag_id
                        records_index.select { |key, _| key[0] == session.content_tag_id }.values.flatten
                      else
                        []
                      end

    enrolled = fetch_enrolled_students
    total_students = enrolled.present? ? enrolled.count : session_records.count
    stats = AttendanceStatsCalculator.calculate_stats(session, session_records, total_students)

    {
      session: session,
      setting: session.setting,
      stats: stats,
      attendance_rate: AttendanceStatsCalculator.calculate_attendance_rate(stats, total_students),
      class_time: AttendanceStatsCalculator.format_class_time(session),
      due: AttendanceStatsCalculator.format_due(session),
      mapped: session.mapped?
    }
  end

  def merge_stats(stats_array)
    result = { present: 0, excused: 0, late: 0, absent: 0, pending: 0 }
    stats_array.each do |s|
      result[:present] += s[:present] || 0
      result[:excused] += s[:excused] || 0
      result[:late] += s[:late] || 0
      result[:absent] += s[:absent] || 0
      result[:pending] += s[:pending] || 0
    end
    result
  end

  def empty_sessions_result
    {
      sessions_by_week: {},
      stats: empty_stats,
      total_sessions: 0
    }
  end

  def empty_student_result
    {
      by_week: {},
      stats: empty_stats,
      user_name: nil,
      user_identifier: nil
    }
  end

  def empty_stats
    { present: 0, excused: 0, late: 0, absent: 0, pending: 0 }
  end

  def status_label(status)
    case status
    when 'present' then '출석'
    when 'excused' then '공결'
    when 'late' then '지각'
    when 'absent' then '결석'
    else '미결'
    end
  end

  # ========================================
  # 수강생 목록 관련
  # ========================================

  # Canvas API로 enrolled 학생 목록 조회 (캐싱)
  def fetch_enrolled_students
    return @enrolled_students if defined?(@enrolled_students)

    @enrolled_students = if @canvas_api
                           course_id = @lti_context.canvas_course_id
                           if course_id.present?
                             enrollments_client = CanvasApi::EnrollmentsClient.new(@canvas_api)
                             enrollments_client.list_students(course_id)
                           end
                         end
  rescue => e
    Rails.logger.error "수강생 목록 조회 실패: #{e.class} - #{e.message}"
    @enrolled_students = nil
  end

  # 레코드를 student_id(identifier) 기준으로 인덱싱
  def build_records_by_student_id(records)
    index = {}
    records.each do |record|
      id = record.student_id
      # priority_ordered이므로 첫 번째가 최우선
      index[id] ||= record
    end
    index
  end

  # enrolled 학생 기반 목록 생성 (전체 수강생 표시)
  def build_students_from_enrolled(session, enrolled, records_by_id)
    enrolled.map do |student|
      # 세션 타입에 따라 식별자 결정
      identifier = session.vod? ? student[:login_id] : student[:email]

      record = identifier.present? ? records_by_id[identifier] : nil

      if record
        {
          record: record,
          student_id: identifier,
          canvas_user_id: student[:user_id],
          user_name: student[:name],
          attendance_state: record.attendance_state,
          status: AttendanceStatsCalculator.convert_state_to_string(record.attendance_state, session: session),
          status_label: record.attendance_state_text,
          teacher_forced: record.teacher_forced?,
          created_at: record.created_at,
          view_percent: record.respond_to?(:percent_viewed) ? record.percent_viewed : record.respond_to?(:attendance_rate) ? record.attendance_rate : nil,
          modified_by_user_id: record.modified_by_user_id
        }
      else
        # 레코드 없는 학생: 자동 판정
        auto_status = AttendanceStatsCalculator.resolve_pending_status(session)
        auto_state = case auto_status
                     when 'absent' then 1
                     when 'late' then 2
                     when 'excused' then 3
                     when 'present' then 4
                     else 0
                     end
        {
          record: nil,
          student_id: identifier,
          canvas_user_id: student[:user_id],
          user_name: student[:name],
          attendance_state: auto_state,
          status: auto_status,
          status_label: status_label(auto_status),
          teacher_forced: false,
          created_at: nil,
          view_percent: nil,
          modified_by_user_id: nil
        }
      end
    end.sort_by { |s| s[:user_name].to_s }
  end

  # 레코드 기반 목록 생성 (폴백: Canvas API 없을 때)
  def build_students_from_records(session, records)
    records.map do |record|
      {
        record: record,
        student_id: record.student_id,
        user_name: record.respond_to?(:user_name) ? record.user_name : record.user_email,
        attendance_state: record.attendance_state,
        status: AttendanceStatsCalculator.convert_state_to_string(record.attendance_state, session: session),
        status_label: record.attendance_state_text,
        teacher_forced: record.teacher_forced?,
        created_at: record.created_at,
        view_percent: record.respond_to?(:percent_viewed) ? record.percent_viewed : record.respond_to?(:attendance_rate) ? record.attendance_rate : nil,
        modified_by_user_id: record.modified_by_user_id
      }
    end
  end
end
