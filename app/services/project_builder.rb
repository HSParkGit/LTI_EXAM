# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Project 생성/수정 및 여러 Canvas Assignment 생성
# - Canvas API를 통한 Assignment 관리
# - LTI Tool DB에 Project만 저장, Assignment는 Canvas에 저장
# - 원본 Canvas의 ProjectBuilder 로직 참고
#
# 기술적 고려사항:
# - CanvasApi::AssignmentsClient 사용
# - Assignment ID만 Project에 저장
# - Peer Review는 체크박스로 선택 가능
# - Assignment Group, Group Category 지원
#
# 사용 시 고려사항:
# - CanvasApi::Client가 초기화되어 있어야 함
# - LtiContext가 생성되어 있어야 함
# - Canvas User ID는 LTI Claims에서 추출
class ProjectBuilder
  class ProjectCreationError < StandardError; end

  def initialize(lti_context:, canvas_api:, lti_user_sub:, project: nil)
    @lti_context = lti_context
    @canvas_api = canvas_api
    @lti_user_sub = lti_user_sub
    @project = project
    @assignments_client = CanvasApi::AssignmentsClient.new(@canvas_api)
  end

  # Project 생성 (여러 Assignment 지원)
  # @param project_params [Hash] Project 파라미터
  # @return [Project] 생성된 Project
  def create_project(project_params)
    project_name = project_params[:name]

    unless project_name.present?
      raise ProjectCreationError, "프로젝트 이름은 필수입니다."
    end

    # 공통 설정 추출
    assignment_group_id = project_params[:assignment_group_id]
    group_category_id = project_params[:group_category_id]
    grade_group_students_individually = project_params[:grade_group_students_individually] || false
    publish_immediately = project_params[:publish] == 'true' || project_params[:publish] == true

    # 여러 Assignment 생성
    # Rails nested attributes는 Hash 형태로 전달됨: {"0"=>{...}, "1"=>{...}}
    # ActionController::Parameters를 Hash로 변환 후 values로 Array 변환
    assignments_params_raw = project_params[:assignments] || {}
    assignments_params = if assignments_params_raw.respond_to?(:to_h)
      # ActionController::Parameters 또는 Hash인 경우
      assignments_params_raw.to_h.values
    elsif assignments_params_raw.is_a?(Array)
      # 이미 Array인 경우
      assignments_params_raw
    else
      # 그 외의 경우 빈 Array
      []
    end
    assignments = assignments_params.filter_map.with_index do |assignment_params, index|
      # 삭제 플래그 확인
      next nil if assignment_params[:_destroy].to_s == 'true'

      # Assignment 생성
      assignment = create_assignment(
        assignment_params,
        assignment_group_id: assignment_group_id,
        group_category_id: group_category_id,
        grade_group_students_individually: grade_group_students_individually,
        position: index + 1
      )

      # Publish 옵션
      if publish_immediately && assignment['workflow_state'] != 'published'
        publish_assignment(assignment['id'])
      end

      assignment
    end

    if assignments.empty?
      raise ProjectCreationError, "최소 1개의 Assignment가 필요합니다."
    end

    # Project 생성
    project = Project.new(
      lti_context: @lti_context,
      name: project_name,
      lti_user_sub: @lti_user_sub,
      assignment_ids: assignments.map { |a| a['id'].to_s }
    )

    unless project.save
      raise ProjectCreationError, "프로젝트 생성 실패: #{project.errors.full_messages.join(', ')}"
    end

    project
  rescue CanvasApi::Client::ApiError => e
    Rails.logger.error "Canvas Assignment 생성 실패: #{e.message}"
    raise ProjectCreationError, "과제 생성에 실패했습니다: #{e.message}"
  end

  # Project 수정 (Assignment 추가/수정/삭제)
  # @param project_params [Hash] Project 파라미터
  # @return [Project] 수정된 Project
  def update_project(project_params)
    unless @project
      raise ProjectCreationError, "수정할 프로젝트가 지정되지 않았습니다."
    end

    # 프로젝트 이름 수정
    project_name = project_params[:name]
    @project.name = project_name if project_name.present?

    # 공통 설정 추출
    assignment_group_id = project_params[:assignment_group_id]
    group_category_id = project_params[:group_category_id]
    grade_group_students_individually = project_params[:grade_group_students_individually] || false
    publish_action = project_params[:publish].to_s
    publish_immediately = publish_action == 'true'
    unpublish_immediately = publish_action == 'unpublish'

    # Assignment 처리
    # Rails nested attributes는 Hash 형태로 전달됨: {"0"=>{...}, "1"=>{...}}
    # ActionController::Parameters를 Hash로 변환 후 values로 Array 변환
    assignments_params_raw = project_params[:assignments] || {}
    assignments_params = if assignments_params_raw.respond_to?(:to_h)
      # ActionController::Parameters 또는 Hash인 경우
      assignments_params_raw.to_h.values
    elsif assignments_params_raw.is_a?(Array)
      # 이미 Array인 경우
      assignments_params_raw
    else
      # 그 외의 경우 빈 Array
      []
    end
    assignments = assignments_params.filter_map.with_index do |assignment_params, index|
      destroy_flag = assignment_params[:_destroy].to_s

      # 삭제
      if destroy_flag == 'true' && assignment_params[:id].present?
        delete_assignment(assignment_params[:id])
        next nil
      end

      # 신규 생성
      if assignment_params[:id].blank?
        assignment = create_assignment(
          assignment_params,
          assignment_group_id: assignment_group_id,
          group_category_id: group_category_id,
          grade_group_students_individually: grade_group_students_individually,
          position: index + 1
        )
      else
        # 기존 수정
        assignment = update_assignment(
          assignment_params,
          assignment_group_id: assignment_group_id,
          group_category_id: group_category_id,
          grade_group_students_individually: grade_group_students_individually,
          position: index + 1
        )
      end

      # Publish 옵션
      if publish_immediately && assignment['workflow_state'] != 'published'
        publish_assignment(assignment['id'])
      end

      # Unpublish 옵션
      if unpublish_immediately && assignment['workflow_state'] == 'published'
        unpublish_assignment(assignment['id'])
      end

      assignment
    end

    # Assignment IDs 업데이트
    @project.assignment_ids = assignments.map { |a| a['id'].to_s }

    unless @project.save
      raise ProjectCreationError, "프로젝트 수정 실패: #{@project.errors.full_messages.join(', ')}"
    end

    @project
  rescue CanvasApi::Client::ApiError => e
    Rails.logger.error "Canvas Assignment 수정 실패: #{e.message}"
    raise ProjectCreationError, "과제 수정에 실패했습니다: #{e.message}"
  end

  private

  # Canvas Assignment 생성
  def create_assignment(assignment_params, assignment_group_id: nil, group_category_id: nil, grade_group_students_individually: false, position: 1)
    course_id = @lti_context.canvas_course_id

    unless course_id.present?
      raise ProjectCreationError, "Canvas Course ID를 찾을 수 없습니다."
    end

    # Assignment 파라미터 빌드
    canvas_params = build_assignment_params(
      assignment_params,
      assignment_group_id: assignment_group_id,
      group_category_id: group_category_id,
      grade_group_students_individually: grade_group_students_individually,
      position: position
    )

    @assignments_client.create(course_id, canvas_params)
  end

  # Canvas Assignment 수정
  # 주의: update 시에는 명시적으로 전달된 필드만 업데이트 (기존 값 유지)
  def update_assignment(assignment_params, assignment_group_id: nil, group_category_id: nil, grade_group_students_individually: false, position: 1)
    course_id = @lti_context.canvas_course_id
    assignment_id = assignment_params[:id]

    unless course_id.present? && assignment_id.present?
      raise ProjectCreationError, "Canvas Course ID 또는 Assignment ID를 찾을 수 없습니다."
    end

    # Update용 파라미터 빌드 (명시적으로 전달된 필드만 포함)
    canvas_params = build_update_assignment_params(
      assignment_params,
      assignment_group_id: assignment_group_id,
      group_category_id: group_category_id,
      grade_group_students_individually: grade_group_students_individually,
      position: position
    )

    @assignments_client.update(course_id, assignment_id, { assignment: canvas_params })
  end

  # Canvas Assignment 삭제
  def delete_assignment(assignment_id)
    course_id = @lti_context.canvas_course_id

    unless course_id.present? && assignment_id.present?
      raise ProjectCreationError, "Canvas Course ID 또는 Assignment ID를 찾을 수 없습니다."
    end

    @assignments_client.delete(course_id, assignment_id)
  end

  # Assignment Publish
  def publish_assignment(assignment_id)
    course_id = @lti_context.canvas_course_id
    @assignments_client.update(course_id, assignment_id, { assignment: { published: true } })
  end

  # Assignment Unpublish
  def unpublish_assignment(assignment_id)
    course_id = @lti_context.canvas_course_id
    @assignments_client.update(course_id, assignment_id, { assignment: { published: false } })
  end

  # Assignment 파라미터 빌드 (생성용)
  # 기본값: 0점, 내일 마감, 파일 업로드
  def build_assignment_params(assignment_params, assignment_group_id:, group_category_id:, grade_group_students_individually:, position:)
    # 기본 마감일: 내일 23:59
    default_due_at = (Time.current.end_of_day + 1.day).strftime('%Y-%m-%dT%H:%M:%SZ')

    params = {
      name: assignment_params[:name] || assignment_params[:title],
      due_at: format_datetime_for_canvas(assignment_params[:due_at]) || default_due_at,
      points_possible: assignment_params[:points_possible] || 0,
      grading_type: 'points',
      submission_types: ['online_upload'],
      position: position,
      workflow_state: 'unpublished'
    }

    # Assignment Group
    params[:assignment_group_id] = assignment_group_id if assignment_group_id.present?

    # Group Category (그룹 과제)
    if group_category_id.present?
      params[:group_category_id] = group_category_id
      params[:grade_group_students_individually] = grade_group_students_individually
    end

    # nil 값 제거
    params.compact
  end

  # Assignment 파라미터 빌드 (수정용)
  # 명시적으로 전달된 필드만 포함 (기존 값 유지를 위해 기본값 설정 안 함)
  def build_update_assignment_params(assignment_params, assignment_group_id:, group_category_id:, grade_group_students_individually:, position:)
    params = {}

    # 이름이 전달된 경우만 업데이트
    name = assignment_params[:name] || assignment_params[:title]
    params[:name] = name if name.present?

    # 위치
    params[:position] = position

    # Assignment Group (명시적으로 전달된 경우)
    params[:assignment_group_id] = assignment_group_id if assignment_group_id.present?

    # Group Category (그룹 과제)
    if group_category_id.present?
      params[:group_category_id] = group_category_id
      params[:grade_group_students_individually] = grade_group_students_individually
    end

    # nil 값 제거
    params.compact
  end

  # Submission Types 파싱
  def parse_submission_types(submission_types)
    return ['online_url', 'online_upload'] if submission_types.blank?

    if submission_types.is_a?(String)
      submission_types.split(',').map(&:strip)
    elsif submission_types.is_a?(Array)
      submission_types
    else
      ['online_url', 'online_upload']
    end
  end

  # Allowed Extensions 파싱
  def parse_allowed_extensions(allowed_extensions)
    return nil if allowed_extensions.blank?

    if allowed_extensions.is_a?(String)
      allowed_extensions.split(',').map(&:strip)
    elsif allowed_extensions.is_a?(Array)
      allowed_extensions
    else
      nil
    end
  end

  # Canvas API용 datetime 형식 변환
  # Canvas API는 ISO 8601 형식의 datetime을 요구함: YYYY-MM-DDTHH:MM:SSZ (초와 UTC 표시자 필수)
  # 빈 문자열이나 nil은 nil로 반환
  # @param datetime_value [String, nil] 폼에서 전달된 datetime 값 (예: "2026-01-17T17:51")
  # @return [String, nil] ISO 8601 형식의 datetime 문자열 (YYYY-MM-DDTHH:MM:SSZ) 또는 nil
  def format_datetime_for_canvas(datetime_value)
    return nil if datetime_value.blank?
    
    begin
      # "2026-01-17T17:51" 형식을 파싱 (로컬 타임존으로 해석)
      parsed_time = DateTime.parse(datetime_value.to_s)
      
      # Canvas API는 UTC 형식을 요구하므로 UTC로 변환
      # 초가 없으면 00으로 설정
      utc_time = parsed_time.utc
      
      # YYYY-MM-DDTHH:MM:SSZ 형식으로 변환 (Canvas API 요구사항)
      utc_time.strftime('%Y-%m-%dT%H:%M:%SZ')
    rescue ArgumentError, TypeError => e
      Rails.logger.warn "Datetime 파싱 실패: #{datetime_value}, 에러: #{e.message}"
      # 파싱 실패 시 nil 반환
      nil
    end
  end
end

