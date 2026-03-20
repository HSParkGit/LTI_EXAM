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
  before_action :set_locale
  before_action :set_session, only: [:show, :edit, :update, :update_attendance, :bulk_update_attendance, :student_history, :download_excel]
  before_action :authorize_instructor!, only: [:edit, :update, :update_attendance, :bulk_update_attendance, :student_lectures, :student_lectures_excel, :student_history, :download_excel, :bulk_edit, :bulk_update]

  # 세션 목록
  # 교수: Auto-Sync 후 전체 세션 + 통계
  # 학생: 본인 출결 현황
  def index
    @user_role = determine_course_user_role

    # TODO: 테스트용 Auto-Sync 비활성화 - 검수 후 복원
    # if @user_role == :instructor
    #   sync_result = AttendanceSyncService.new(
    #     lti_context: @lti_context,
    #     canvas_api: @canvas_api
    #   ).sync!
    #
    #   if sync_result[:created] > 0 || sync_result[:restored] > 0 || sync_result[:soft_deleted] > 0
    #     Rails.logger.info "Auto-Sync 완료: #{sync_result}"
    #   end
    # end

    result = mock_index_data  # TODO: 테스트 후 @service.sessions_with_statistics로 복원
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
      @students = mock_show_data  # TODO: 테스트 후 복원
      @stats = mock_session_stats(MOCK_SESSIONS_INFO.find { |s| s[:week] == @session.week && s[:lesson] == @session.lesson_id }&.dig(:key) || MOCK_SESSIONS_INFO.first[:key])  # TODO: 복원
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
    @student_identifier = target_identifier || @attendance[:user_identifier]

    # 테이블용 주차→차시 그룹핑 데이터
    if @attendance[:by_week].present?
      @processed_data = build_processed_data(@attendance[:by_week])
    end

    respond_to do |format|
      format.html
      format.json { render json: build_student_detail_mock }  # TODO: 테스트 후 build_student_detail_json으로 복원
    end
  end

  # 학생용: 내 출결 현황
  def my_attendance
    @user_role = determine_course_user_role
    @attendance = @service.student_attendance(nil)
    @student_identifier = @attendance[:user_identifier]

    if @attendance[:by_week].present?
      @processed_data = build_processed_data(@attendance[:by_week])
    end

    render :student_detail
  end

  # 학생×세션 매트릭스 (교수용)
  def student_lectures
    result = mock_student_lectures_data  # TODO: 테스트 후 @service.student_lectures_matrix로 복원
    @students = result[:students]
    @lesson_slots_by_week = result[:lesson_slots_by_week]
  end

  # 일괄 설정 편집 (교수용)
  def bulk_edit
    @sessions = @lti_context.attendance_sessions.active
                            .includes(:vod_setting, :live_setting)
                            .ordered

    # 검색
    if params[:q].present?
      @sessions = @sessions.where('title ILIKE ?', "%#{params[:q]}%")
    end

    # 타입 필터
    if params[:type].present? && %w[vod live].include?(params[:type])
      @sessions = @sessions.where(attendance_type: params[:type])
    end

    @total_count = @sessions.count
    @per_page = 15
    @page = [params[:page].to_i, 1].max
    @total_pages = (@total_count.to_f / @per_page).ceil
    @sessions = @sessions.offset((@page - 1) * @per_page).limit(@per_page)
  end

  # 일괄 설정 저장
  def bulk_update
    sessions_params = params[:sessions] || {}
    updated = 0
    errors = []

    sessions_params.each do |session_id, setting_params|
      session = @lti_context.attendance_sessions.active.find_by(id: session_id)
      next unless session

      setting = session.setting
      next unless setting

      permitted = if session.vod?
                    setting_params.permit(:allow_attendance, :percent_required, :allow_tardiness,
                                         :unlock_at, :lock_at, :attendance_finish_at, :tardiness_finish_at)
                  else
                    setting_params.permit(:allow_attendance, :attendance_threshold, :allow_tardiness,
                                         :tardiness_threshold, :start_time, :duration)
                  end

      if setting.update(permitted)
        updated += 1
      else
        errors << { title: session.title, messages: setting.errors.full_messages }
      end
    end

    if errors.any?
      flash[:error] = "#{updated}건 저장, #{errors.size}건 실패: #{errors.map { |e| e[:title] }.join(', ')}"
    else
      flash[:notice] = "#{updated}건 설정이 저장되었습니다."
    end

    redirect_to bulk_edit_attendance_index_path(page: params[:page], q: params[:q], type: params[:type])
  end

  # 학생 히스토리 API (JSON) - 히스토리 모달용
  # TODO: 테스트용 목 데이터 - 확인 후 원본으로 복원
  def student_history
    identifier = params[:student_identifier]
    return render(json: { error: '학생 식별자가 필요합니다.' }, status: :bad_request) if identifier.blank?

    session_info = MOCK_SESSIONS_INFO.find { |s| s[:week] == @session.week && s[:lesson] == @session.lesson_id }
    current_status = 'pending'
    if session_info
      MOCK_SESSIONS_INFO.select { |s| s[:week] == session_info[:week] && s[:lesson] == session_info[:lesson] }
                        .each { |m| current_status = MOCK_STATUSES[m[:key]]&.dig(identifier) || current_status }
    end

    is_vod = @session.attendance_type == 'vod'
    if is_vod
      records = [
        { number: 5, date: '2026-03-18', time: '02:30 PM - 03:15 PM', view_rate: '85% (45분 0초)', notes: '-' },
        { number: 4, date: '2026-03-17', time: '10:00 AM - 10:25 AM', view_rate: '65% (25분 0초)', notes: '-' },
        { number: 3, date: '2026-03-16', time: '08:45 PM - 09:00 PM', view_rate: '42% (15분 0초)', notes: '-' },
        { number: 2, date: '2026-03-15', time: '11:10 AM - 11:22 AM', view_rate: '25% (12분 0초)', notes: '-' },
        { number: 1, date: '2026-03-14', time: '09:00 AM - 09:08 AM', view_rate: '10% (8분 0초)', notes: '-' }
      ]
      raw_records = [
        { number: 8, date: '2026-03-18', time: '03:05 PM - 03:15 PM', view_rate: '85%', notes: '-' },
        { number: 7, date: '2026-03-18', time: '02:30 PM - 02:50 PM', view_rate: '72%', notes: '-' },
        { number: 6, date: '2026-03-17', time: '10:15 AM - 10:25 AM', view_rate: '65%', notes: '-' },
        { number: 5, date: '2026-03-17', time: '10:00 AM - 10:10 AM', view_rate: '50%', notes: '-' },
        { number: 4, date: '2026-03-16', time: '08:45 PM - 09:00 PM', view_rate: '42%', notes: '-' },
        { number: 3, date: '2026-03-15', time: '11:10 AM - 11:22 AM', view_rate: '25%', notes: '-' },
        { number: 2, date: '2026-03-14', time: '09:04 AM - 09:08 AM', view_rate: '10%', notes: '-' },
        { number: 1, date: '2026-03-14', time: '09:00 AM - 09:03 AM', view_rate: '5%', notes: '-' }
      ]
    else
      records = [
        { number: 4, date: '2026-03-19', time: '03:00 PM - 03:30 PM', view_rate: '100% (30분 0초)', notes: '-' },
        { number: 3, date: '2026-03-19', time: '02:00 PM - 02:45 PM', view_rate: '75% (45분 0초)', notes: '-' },
        { number: 2, date: '2026-03-19', time: '02:50 PM - 02:55 PM', view_rate: '80% (5분 0초)', notes: '-' },
        { number: 1, date: '2026-03-19', time: '02:00 PM - 02:03 PM', view_rate: '5% (3분 0초)', notes: '-' }
      ]
      raw_records = records
    end

    if %w[late absent].include?(current_status)
      forced = { number: records.first[:number] + 1, date: '2026-03-20', time: '02:15 PM',
                 view_rate: '-', notes: "#{current_status.capitalize} - 출결 상태 변경" }
      records.unshift(forced)
      records.each_with_index { |r, i| r[:number] = records.size - i }
      raw_records.unshift(forced.dup)
      raw_records.each_with_index { |r, i| r[:number] = raw_records.size - i }
    end

    render json: {
      success: true,
      session: { id: @session.id, title: @session.full_title, type: @session.attendance_type },
      current_status: current_status,
      records: records,
      raw_records: raw_records
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

  # 로케일 설정 (Canvas LTI locale → 시스템 기본)
  SUPPORTED_LOCALES = %w[ko en].freeze

  def set_locale
    canvas_locale = @lti_claims[:locale] || @lti_claims['locale']
    if canvas_locale.present?
      normalized = canvas_locale.to_s.split('-').first # "ko-KR" → "ko"
      if SUPPORTED_LOCALES.include?(normalized)
        I18n.locale = normalized
        return
      end
    end

    I18n.locale = :ko
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

  # =====================================================
  # TODO: 테스트용 목 데이터 블록 - 검수 완료 후 전체 삭제
  # =====================================================

  MOCK_STUDENTS = [
    { user_id: '1001', name: '김영희', login_id: 'student001', email: 'student001@test.com' },
    { user_id: '1002', name: '이철수', login_id: 'student002', email: 'student002@test.com' },
    { user_id: '1003', name: '박민수', login_id: 'student003', email: 'student003@test.com' },
    { user_id: '1004', name: '정수진', login_id: 'student004', email: 'student004@test.com' },
    { user_id: '1005', name: '최준혁', login_id: 'student005', email: 'student005@test.com' }
  ].freeze

  # 학생별 세션별 상태 (session_key → student_login → status)
  MOCK_STATUSES = {
    '1-1-vod'  => { 'student001' => 'present', 'student002' => 'present', 'student003' => 'absent',  'student004' => 'present', 'student005' => 'pending' },
    '1-2-vod'  => { 'student001' => 'present', 'student002' => 'late',    'student003' => 'absent',  'student004' => 'present', 'student005' => 'pending' },
    '1-3-live' => { 'student001' => 'present', 'student002' => 'present', 'student003' => 'present', 'student004' => 'late',    'student005' => 'absent'  },
    '2-1-vod'  => { 'student001' => 'late',    'student002' => 'present', 'student003' => 'present', 'student004' => 'present', 'student005' => 'absent'  },
    '2-2a-vod' => { 'student001' => 'present', 'student002' => 'present', 'student003' => 'late',    'student004' => 'present', 'student005' => 'pending' },
    '2-2b-vod' => { 'student001' => 'absent',  'student002' => 'present', 'student003' => 'present', 'student004' => 'present', 'student005' => 'pending' },
    '2-3-live' => { 'student001' => 'present', 'student002' => 'absent',  'student003' => 'present', 'student004' => 'present', 'student005' => 'present' },
    '3-1a-vod' => { 'student001' => 'late',    'student002' => 'present', 'student003' => 'absent',  'student004' => 'present', 'student005' => 'late'    },
    '3-1b-live'=> { 'student001' => 'present', 'student002' => 'present', 'student003' => 'absent',  'student004' => 'present', 'student005' => 'present' },
    '3-2-vod'  => { 'student001' => 'absent',  'student002' => 'present', 'student003' => 'pending', 'student004' => 'present', 'student005' => 'absent'  },
    '3-3-live' => { 'student001' => 'present', 'student002' => 'present', 'student003' => 'late',    'student004' => 'present', 'student005' => 'pending' }
  }.freeze

  MOCK_SESSIONS_INFO = [
    { key: '1-1-vod',   week: 1, lesson: 1, title: '강의 소개 및 오리엔테이션', type: 'vod',  time: '03/03 09:00 ~ 03/10 23:59', due: '03/10 23:59' },
    { key: '1-2-vod',   week: 1, lesson: 2, title: '기초 이론 개요',           type: 'vod',  time: '03/03 09:00 ~ 03/10 23:59', due: '03/10 23:59' },
    { key: '1-3-live',  week: 1, lesson: 3, title: '1주차 실시간 Q&A',         type: 'live', time: '03/05 14:00 ~ 03/05 15:30', due: '-' },
    { key: '2-1-vod',   week: 2, lesson: 1, title: '데이터 구조 기본',          type: 'vod',  time: '03/10 09:00 ~ 03/17 23:59', due: '03/17 23:59' },
    { key: '2-2a-vod',  week: 2, lesson: 2, title: '알고리즘 분석 (1)',         type: 'vod',  time: '03/10 09:00 ~ 03/17 23:59', due: '03/17 23:59' },
    { key: '2-2b-vod',  week: 2, lesson: 2, title: '알고리즘 분석 (2)',         type: 'vod',  time: '03/10 09:00 ~ 03/17 23:59', due: '03/17 23:59' },
    { key: '2-3-live',  week: 2, lesson: 3, title: '2주차 실시간 토론',         type: 'live', time: '03/12 14:00 ~ 03/12 15:30', due: '-' },
    { key: '3-1a-vod',  week: 3, lesson: 1, title: '정렬과 탐색 이론',          type: 'vod',  time: '03/17 09:00 ~ 03/24 23:59', due: '03/24 23:59' },
    { key: '3-1b-live', week: 3, lesson: 1, title: '정렬과 탐색 실습',          type: 'live', time: '03/19 10:00 ~ 03/19 11:30', due: '-' },
    { key: '3-2-vod',   week: 3, lesson: 2, title: '그래프 이론',              type: 'vod',  time: '03/17 09:00 ~ 03/24 23:59', due: '03/24 23:59' },
    { key: '3-3-live',  week: 3, lesson: 3, title: '3주차 실시간 강의',         type: 'live', time: '03/19 14:00 ~ 03/19 15:30', due: '-' }
  ].freeze

  def mock_count_stats(keys, login_id)
    stats = { present: 0, late: 0, absent: 0, pending: 0, excused: 0 }
    keys.each do |k|
      s = MOCK_STATUSES[k]&.dig(login_id) || 'pending'
      stats[s.to_sym] = (stats[s.to_sym] || 0) + 1
    end
    stats
  end

  def mock_session_stats(session_key)
    statuses = MOCK_STATUSES[session_key] || {}
    stats = { present: 0, late: 0, absent: 0, pending: 0, excused: 0 }
    statuses.each_value { |s| stats[s.to_sym] += 1 }
    stats
  end

  def mock_index_data
    total_stats = { present: 0, late: 0, absent: 0, pending: 0, excused: 0 }
    all_sessions = @lti_context.attendance_sessions.active.includes(:vod_setting, :live_setting).ordered

    sessions_by_week = {}
    MOCK_SESSIONS_INFO.each do |info|
      week = info[:week]
      sessions_by_week[week] ||= []
      stats = mock_session_stats(info[:key])
      total = MOCK_STUDENTS.size
      rate = ((stats[:present] + stats[:excused]).to_f / total * 100).round(1)
      stats.each { |k, v| total_stats[k] += v }

      session = all_sessions.find { |s| s.title == info[:title] } ||
                all_sessions.find { |s| s.week == info[:week] && s.lesson_id == info[:lesson] && s.attendance_type == info[:type] }
      next unless session

      sessions_by_week[week] << {
        session: session,
        setting: session.setting,
        stats: stats,
        attendance_rate: rate,
        class_time: info[:time],
        due: info[:due],
        mapped: true
      }
    end

    { sessions_by_week: sessions_by_week, stats: total_stats, total_sessions: MOCK_SESSIONS_INFO.size }
  end

  def mock_find_session(info)
    @_mock_all_sessions ||= @lti_context.attendance_sessions.active.includes(:vod_setting, :live_setting).to_a
    @_mock_all_sessions.find { |s| s.title == info[:title] } ||
      @_mock_all_sessions.find { |s| s.week == info[:week] && s.lesson_id == info[:lesson] && s.attendance_type == info[:type] }
  end

  def mock_show_data
    session_info = MOCK_SESSIONS_INFO.find { |s| s[:title] == @session.title } ||
                   MOCK_SESSIONS_INFO.find { |s| s[:week] == @session.week && s[:lesson] == @session.lesson_id && s[:type] == @session.attendance_type }
    session_info ||= MOCK_SESSIONS_INFO.find { |s| s[:week] == @session.week }
    return unless session_info

    statuses = MOCK_STATUSES[session_info[:key]] || {}
    MOCK_STUDENTS.map do |st|
      login = st[:login_id]
      status = statuses[login] || 'pending'
      {
        record: nil,
        student_id: login,
        canvas_user_id: st[:user_id],
        user_name: st[:name],
        attendance_state: { 'present' => 4, 'late' => 2, 'absent' => 1, 'pending' => 0, 'excused' => 3 }[status],
        status: status,
        status_label: status,
        teacher_forced: false,
        created_at: nil,
        view_percent: nil,
        modified_by_user_id: nil
      }
    end
  end

  def mock_student_lectures_data
    lesson_slots_by_week = {}
    MOCK_SESSIONS_INFO.group_by { |s| [s[:week], s[:lesson]] }.sort.each do |(week, lesson_id), infos|
      lesson_slots_by_week[week] ||= []
      sessions = infos.map do |info|
        mock_find_session(info) ||
          OpenStruct.new(id: info[:key].hash.abs, week: info[:week], lesson_id: info[:lesson], title: info[:title], attendance_type: info[:type], vod?: info[:type] == 'vod')
      end
      lesson_slots_by_week[week] << { week: week, lesson_id: lesson_id, sessions: sessions }
    end

    students = MOCK_STUDENTS.map do |st|
      login = st[:login_id]
      stats = { present: 0, late: 0, absent: 0, pending: 0, excused: 0 }
      slot_statuses = {}

      MOCK_SESSIONS_INFO.group_by { |s| [s[:week], s[:lesson]] }.sort.each do |(week, lesson_id), infos|
        slot_key = "#{week}-#{lesson_id}"
        items = infos.map do |info|
          s = MOCK_STATUSES[info[:key]]&.dig(login) || 'pending'
          sess = mock_find_session(info)
          { session_id: sess&.id || info[:key].hash.abs, title: info[:title], type: info[:type], status: s, identifier: login }
        end

        priority = AttendanceStatsCalculator.determine_priority_status(items.map { |i| i[:status] })
        stats[priority.to_sym] += 1
        slot_statuses[slot_key] = { status: priority, items: items }
      end

      { user_id: st[:user_id], name: st[:name], login_id: login, email: st[:email], stats: stats, slot_statuses: slot_statuses }
    end.sort_by { |s| s[:name].to_s }

    { students: students, lesson_slots_by_week: lesson_slots_by_week }
  end

  def build_student_detail_mock
    login = params[:student_identifier] || 'student001'
    student = MOCK_STUDENTS.find { |s| s[:login_id] == login || s[:email] == login }
    student_name = student ? student[:name] : login

    stats = mock_count_stats(MOCK_SESSIONS_INFO.map { |s| s[:key] }, login)

    weeks = MOCK_SESSIONS_INFO.group_by { |s| s[:week] }.sort.map do |week, week_infos|
      lessons = week_infos.group_by { |s| s[:lesson] }.sort.map do |lesson_id, lesson_infos|
        lectures = lesson_infos.map do |info|
          s = MOCK_STATUSES[info[:key]]&.dig(login) || 'pending'
          sess = mock_find_session(info)
          { session_id: sess&.id || info[:key].hash.abs, title: info[:title], attendance_type: info[:type],
            class_time: info[:time], due: info[:due], status: s, status_label: s }
        end
        lesson_status = AttendanceStatsCalculator.determine_priority_status(lectures.map { |l| l[:status] })
        { lesson_id: lesson_id, lesson_status: lesson_status, lectures: lectures }
      end
      { week: week, lessons: lessons }
    end

    { success: true, student_name: student_name, student_identifier: login, stats: stats, processed_data: weeks }
  end

  # student_detail JSON 응답 빌더
  def build_student_detail_json
    {
      success: true,
      student_name: @attendance[:user_name],
      student_identifier: @student_identifier,
      stats: @attendance[:stats],
      processed_data: (@processed_data || []).map do |week_group|
        {
          week: week_group[:week],
          lessons: week_group[:lessons].map do |lesson|
            {
              lesson_id: lesson[:lesson_id],
              lesson_status: lesson[:lesson_status],
              lectures: lesson[:lectures].map do |lec|
                {
                  session_id: lec[:session].id,
                  title: lec[:title],
                  attendance_type: lec[:attendance_type],
                  class_time: lec[:class_time],
                  due: lec[:due],
                  status: lec[:status],
                  status_label: lec[:status_label]
                }
              end
            }
          end
        }
      end
    }
  end

  # student_detail 테이블용 주차→차시 그룹핑 데이터 생성
  def build_processed_data(by_week)
    by_week.keys.sort.map do |week|
      entries = by_week[week]
      lessons = entries.group_by { |d| d[:session].lesson_id }.sort.map do |lesson_id, lesson_entries|
        statuses = lesson_entries.map { |e| e[:status] }
        lesson_status = AttendanceStatsCalculator.determine_priority_status(statuses)

        {
          lesson_id: lesson_id,
          lesson_status: lesson_status,
          lectures: lesson_entries.map do |entry|
            s = entry[:session]
            {
              session: s,
              title: s.title.presence || s.week_lesson_label,
              attendance_type: s.attendance_type,
              class_time: AttendanceStatsCalculator.format_class_time(s),
              due: AttendanceStatsCalculator.format_due(s),
              status: entry[:status],
              status_label: entry[:status_label]
            }
          end
        }
      end

      { week: week, lessons: lessons }
    end
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
