# frozen_string_literal: true

#
# 출결 강제 변경 서비스 (재작성)
# Canvas 원본 UpdateService 포팅
#
# 핵심 기능:
# - panopto_view_results / zoom_view_results 직접 UPDATE
# - 기존 레코드 없으면 새로 생성 (upsert)
# - teacher_forced_change = 1 설정
# - 변경한 교수 정보 기록
#
class AttendanceUpdateService
  class AttendanceUpdateError < StandardError; end

  # 출결 상태 상수
  VALID_STATES = [0, 1, 2, 3, 4].freeze

  def initialize(session:, student_identifier:, modifier_claims:)
    @session = session
    @student_identifier = student_identifier
    @modifier_claims = modifier_claims
  end

  # 출결 상태 강제 변경
  #
  # @param attendance_state [Integer] 새 출결 상태 (0-4)
  # @return [Hash] { success: true/false, record: ..., error: ... }
  def update(attendance_state:)
    validate_state!(attendance_state)
    validate_session!

    ActiveRecord::Base.transaction do
      record = find_or_create_record
      update_record!(record, attendance_state)

      { success: true, record: record }
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "출결 변경 실패 (Validation): #{e.message}"
    { success: false, error: e.record.errors.full_messages.join(', ') }
  rescue AttendanceUpdateError => e
    Rails.logger.error "출결 변경 실패: #{e.message}"
    { success: false, error: e.message }
  rescue StandardError => e
    Rails.logger.error "출결 변경 실패 (Unknown): #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    { success: false, error: '출결 변경 중 오류가 발생했습니다.' }
  end

  private

  def validate_state!(state)
    unless VALID_STATES.include?(state.to_i)
      raise AttendanceUpdateError, "잘못된 출결 상태입니다: #{state}"
    end
  end

  def validate_session!
    unless @session.content_tag_id.present?
      raise AttendanceUpdateError, '세션이 Canvas와 매핑되지 않았습니다.'
    end

    unless @student_identifier.present?
      raise AttendanceUpdateError, '학생 식별자가 없습니다.'
    end
  end

  def find_or_create_record
    if @session.vod?
      find_or_create_panopto_record
    else
      find_or_create_zoom_record
    end
  end

  def find_or_create_panopto_record
    record = PanoptoViewResult.find_by(
      content_tag_id: @session.content_tag_id,
      user_name: @student_identifier
    )

    if record.nil?
      # 기존 레코드에서 session_id 가져오기, 없으면 VodSetting에서
      existing = PanoptoViewResult.find_by(content_tag_id: @session.content_tag_id)
      session_id = existing&.session_id || @session.vod_setting&.session_id || 'unknown'

      record = PanoptoViewResult.new(
        content_tag_id: @session.content_tag_id,
        session_id: session_id,
        user_id: SecureRandom.uuid,
        user_name: @student_identifier,
        attendance_state: PanoptoViewResult::ATTENDANCE_STATE_PENDING
      )
    end

    record
  end

  def find_or_create_zoom_record
    record = ZoomViewResult.find_by(
      content_tag_id: @session.content_tag_id,
      user_email: @student_identifier
    )

    if record.nil?
      # 기존 레코드에서 meeting_id 가져오기, 없으면 LiveSetting에서
      existing = ZoomViewResult.find_by(content_tag_id: @session.content_tag_id)
      meeting_id = existing&.meeting_id || @session.live_setting&.meeting_id || 'unknown'

      record = ZoomViewResult.new(
        content_tag_id: @session.content_tag_id,
        meeting_id: meeting_id,
        user_email: @student_identifier,
        attendance_state: ZoomViewResult::ATTENDANCE_STATE_PENDING
      )
    end

    record
  end

  def update_record!(record, attendance_state)
    modifier_id = extract_modifier_id

    record.assign_attributes(
      attendance_state: attendance_state.to_i,
      teacher_forced_change: 1,
      modified_by_user_id: modifier_id
    )

    record.save!
  end

  def extract_modifier_id
    # Canvas user_id를 추출 (custom parameter에서)
    # 없으면 0 (기본값)
    canvas_user_id = @modifier_claims[:custom_canvas_user_id] ||
                     @modifier_claims['custom_canvas_user_id'] ||
                     @modifier_claims[:canvas_user_id] ||
                     @modifier_claims['canvas_user_id']

    canvas_user_id.to_i
  end
end
