# frozen_string_literal: true

require 'csv'

# 출결 관리 컨트롤러
# LTI Launch 후 ?tool=attendance로 접근
#
# Canvas 설정:
#   - Target Link URI: https://your-tool.com/lti/launch?tool=attendance
#
# 역할별 기능:
#   - 교수: 세션 설정 수정, 학생 출결 조회/변경
#   - 학생: 본인 출결 현황 조회
#
# 세션 생성/삭제는 Auto-Sync로 자동 관리 (AttendanceSyncService)
class AttendanceController < ApplicationController
  before_action :load_lti_claims
  before_action :set_lti_context
  before_action :set_canvas_api_client
  before_action :set_attendance_service
  before_action :set_course_info
  before_action :set_session, only: [:show, :edit, :update, :update_attendance, :bulk_update_attendance, :student_history, :download_excel]
  before_action :authorize_instructor!, only: [:edit, :update, :update_attendance, :bulk_update_attendance, :student_lectures, :student_lectures_excel, :student_history, :download_excel]

  # 세션 목록
  # 교수: Auto-Sync 후 전체 세션 + 통계
  # 학생: 본인 출결 현황
  def index
    @user_role = determine_course_user_role

    # 교수 접속 시 Canvas와 자동 동기화
    if @user_role == :instructor
      sync_result = AttendanceSyncService.new(
        lti_context: @lti_context,
        canvas_api: @canvas_api
      ).sync!

      if sync_result[:created] > 0 || sync_result[:restored] > 0 || sync_result[:soft_deleted] > 0
        Rails.logger.info "Auto-Sync 완료: #{sync_result}"
      end
    end

    result = @service.sessions_with_statistics
    @sessions_by_week = result[:sessions_by_week]
    @stats = result[:stats]
    @total_sessions = result[:total_sessions]
  end

  # 세션 상세
  # 교수: 학생 출결 리스트 + 강제 변경 UI
  # 학생: 본인 출결 상세
  def show
    @user_role = determine_course_user_role

    if @user_role == :instructor
      @students = @service.session_students(@session)
      @stats = @service.session_stats(@session)
    else
      @my_record = @service.my_session_record(@session)
    end
  end

  # 세션 수정 폼 (설정 조정용)
  def edit
    if @session.vod?
      @session.build_vod_setting unless @session.vod_setting
    else
      @session.build_live_setting unless @session.live_setting
    end
  end

  # 세션 수정
  def update
    if @session.update(session_params)
      redirect_to attendance_path(@session), notice: '출결 세션이 수정되었습니다.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 학생 상세 (전체 출결 현황)
  # 교수: 특정 학생의 전체 출결
  # 학생: 본인 전체 출결
  def student_detail
    @user_role = determine_course_user_role

    target_identifier = if @user_role == :instructor && params[:student_identifier].present?
                          params[:student_identifier]
                        end

    @attendance = @service.student_attendance(target_identifier)
  end

  # 학생용: 내 출결 현황
  def my_attendance
    @user_role = determine_course_user_role
    @attendance = @service.student_attendance(nil)
    render :student_detail
  end

  # 학생×세션 매트릭스 (교수용)
  def student_lectures
    result = @service.student_lectures_matrix
    @students = result[:students]
    @lesson_slots_by_week = result[:lesson_slots_by_week]
  end

  # 학생 히스토리 API (JSON) - 히스토리 모달용
  # ViewLogsService 기반: 30분 gap 세션 그룹핑 + 강제 변경 이력 통합
  def student_history
    identifier = params[:student_identifier]
    return render(json: { error: '학생 식별자가 필요합니다.' }, status: :bad_request) if identifier.blank?

    result = AttendanceViewLogsService.new(
      session: @session,
      student_identifier: identifier
    ).call

    # 현재 출결 상태 조회
    current_result = @session.find_student_result(identifier)
    current_status = if current_result
                       AttendanceStatsCalculator.convert_state_to_string(current_result.attendance_state, session: @session)
                     else
                       AttendanceStatsCalculator.resolve_pending_status(@session)
                     end

    render json: {
      success: result[:success],
      session: {
        id: @session.id,
        title: @session.full_title,
        type: @session.attendance_type
      },
      current_status: current_status,
      records: result[:records] || [],
      raw_records: result[:raw_records] || []
    }
  end

  # Excel 다운로드 (CSV)
  def student_lectures_excel
    result = @service.student_lectures_matrix
    students = result[:students]
    lesson_slots_by_week = result[:lesson_slots_by_week]

    all_slots = lesson_slots_by_week.flat_map { |_w, slots| slots }

    csv_data = "\xEF\xBB\xBF" + CSV.generate do |csv|
      # 헤더
      header = ['Name', 'Student Number', 'Present', 'Late', 'Absent', 'Pending']
      all_slots.each { |slot| header << "W#{slot[:week]}-L#{slot[:lesson_id]}" }
      csv << header

      # 데이터
      students.each do |student|
        row = [
          student[:name],
          student[:login_id],
          student[:stats][:present],
          student[:stats][:late],
          student[:stats][:absent],
          student[:stats][:pending]
        ]
        all_slots.each do |slot|
          slot_key = "#{slot[:week]}-#{slot[:lesson_id]}"
          cell = student[:slot_statuses][slot_key]
          row << (cell ? cell[:status] : 'pending')
        end
        csv << row
      end
    end

    send_data csv_data,
              filename: "attendance_#{@lti_context.context_title}_#{Date.today}.csv",
              type: 'text/csv; charset=utf-8'
  end

  # 강제 변경 API (JSON)
  # 교수만 사용 가능
  def update_attendance
    result = AttendanceUpdateService.new(
      session: @session,
      student_identifier: params[:student_identifier],
      modifier_claims: @lti_claims
    ).update(
      attendance_state: params[:state].to_i
    )

    render json: result
  end

  # 벌크 강제 변경 API (JSON)
  # 교수만 사용 가능 - 선택한 학생들 일괄 변경
  def bulk_update_attendance
    identifiers = params[:student_identifiers]
    state = params[:state].to_i

    return render(json: { success: false, error: '학생을 선택해주세요.' }, status: :bad_request) if identifiers.blank?

    results = identifiers.map do |identifier|
      AttendanceUpdateService.new(
        session: @session,
        student_identifier: identifier,
        modifier_claims: @lti_claims
      ).update(attendance_state: state)
    end

    success_count = results.count { |r| r[:success] }
    render json: { success: true, updated: success_count, total: identifiers.count }
  end

  # 세션별 Excel 다운로드 (CSV)
  def download_excel
    students = @service.session_students(@session)

    csv_data = "\xEF\xBB\xBF" + CSV.generate do |csv|
      csv << ['Name', 'Student Number', 'Attendance Status', 'Modified', 'Changed At']
      students.each do |s|
        csv << [
          s[:user_name],
          s[:student_id],
          s[:status_label] || attendance_status_label(s[:status]),
          s[:teacher_forced] ? 'Yes' : 'No',
          s[:created_at].present? ? s[:created_at].in_time_zone('Asia/Seoul').strftime('%Y-%m-%d %H:%M') : '-'
        ]
      end
    end

    send_data csv_data,
              filename: "attendance_W#{@session.week}L#{@session.lesson_id}_#{Date.today}.csv",
              type: 'text/csv; charset=utf-8'
  end

  private

  # LTI Claims 로드 (세션에서)
  def load_lti_claims
    raw_claims = session[:lti_claims]

    if raw_claims.blank? || session[:lti_claims_expires_at] < Time.current
      flash[:error] = '세션이 만료되었습니다. Canvas에서 LTI Tool을 다시 실행해주세요.'
      redirect_to admin_lti_platforms_path
      return nil
    end

    @lti_claims = raw_claims.is_a?(HashWithIndifferentAccess) ? raw_claims : raw_claims.with_indifferent_access
  end

  # LtiContext 설정
  def set_lti_context
    @lti_context = LtiContext.find(session[:lti_context_id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = '코스 정보를 찾을 수 없습니다.'
    redirect_to admin_lti_platforms_path
  end

  # Canvas API Client 설정
  def set_canvas_api_client
    issuer = @lti_claims[:issuer] || @lti_claims['issuer'] || @lti_claims[:iss] || @lti_claims['iss']
    audience = @lti_claims[:audience] || @lti_claims['audience'] || @lti_claims[:aud] || @lti_claims['aud']
    lti_platform = LtiPlatform.find_by(iss: issuer, client_id: audience)

    unless lti_platform
      Rails.logger.warn "Canvas Platform을 찾을 수 없습니다 (iss: #{issuer}, client_id: #{audience})"
      @canvas_api = nil
      return
    end

    access_token = Lti::CanvasApiTokenGenerator.generate(lti_platform)
    @canvas_api = CanvasApi::Client.new(lti_platform.actual_canvas_url, access_token)
  rescue Lti::CanvasApiTokenGenerator::TokenGenerationError => e
    Rails.logger.warn "Canvas API 인증 실패 (출결에서는 무시): #{e.message}"
    @canvas_api = nil
  end

  # AttendanceService 설정
  def set_attendance_service
    @service = AttendanceService.new(
      lti_context: @lti_context,
      lti_claims: @lti_claims,
      canvas_api: @canvas_api
    )
  end

  # 코스 정보 설정 (코스코드, 교수명)
  def set_course_info
    @course_title = @lti_context.context_title
    @course_label = @lti_context.context_label
    @instructor_names = @lti_context.instructor_names

    if @instructor_names.blank? && @canvas_api && @lti_context.canvas_course_id.present?
      begin
        course_data = @canvas_api.get("/courses/#{@lti_context.canvas_course_id}", 'include[]' => 'teachers')
        if course_data && course_data['teachers'].present?
          names = course_data['teachers'].map { |t| t['display_name'] || t['name'] }.compact.join(', ')
          @lti_context.update(instructor_names: names) if names.present?
          @instructor_names = names
        end
      rescue => e
        Rails.logger.warn "교수명 조회 실패: #{e.message}"
      end
    end
  end

  # 세션 설정 (active만)
  def set_session
    @session = @lti_context.attendance_sessions.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = '출결 세션을 찾을 수 없습니다.'
    redirect_to attendance_index_path
  end

  # 교수 권한 확인
  def authorize_instructor!
    unless determine_course_user_role == :instructor
      flash[:error] = '교수만 출결 세션을 관리할 수 있습니다.'
      redirect_to attendance_index_path
    end
  end

  # 해당 코스에서의 사용자 역할 확인
  def determine_course_user_role
    raw_user_role = @lti_claims[:user_role] || @lti_claims['user_role']

    if raw_user_role.present?
      case raw_user_role.to_s.downcase
      when 'instructor', 'teacher', 'administrator'
        return :instructor
      when 'student', 'learner'
        return :student
      end
    end

    user_roles = @lti_claims[:user_roles] || @lti_claims['user_roles'] || []
    if user_roles.any? { |role| role.to_s =~ /Instructor|Teacher|Administrator/i }
      return :instructor
    end

    :student
  end

  # 세션 파라미터 (수정용 - 설정만 허용)
  def session_params
    params.require(:attendance_session).permit(
      :week, :lesson_id, :title,
      vod_setting_attributes: [
        :id, :session_id, :allow_attendance, :allow_tardiness,
        :percent_required, :unlock_at, :lock_at,
        :attendance_finish_at, :tardiness_finish_at, :_destroy
      ],
      live_setting_attributes: [
        :id, :meeting_id, :allow_attendance, :allow_tardiness,
        :attendance_threshold, :tardiness_threshold,
        :start_time, :duration, :_destroy
      ]
    )
  end
end
