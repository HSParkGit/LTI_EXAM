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
    assignments_params = project_params[:assignments] || []
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
    publish_immediately = project_params[:publish] == 'true' || project_params[:publish] == true

    # Assignment 처리
    assignments_params = project_params[:assignments] || []
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
  def update_assignment(assignment_params, assignment_group_id: nil, group_category_id: nil, grade_group_students_individually: false, position: 1)
    course_id = @lti_context.canvas_course_id
    assignment_id = assignment_params[:id]

    unless course_id.present? && assignment_id.present?
      raise ProjectCreationError, "Canvas Course ID 또는 Assignment ID를 찾을 수 없습니다."
    end

    # Assignment 파라미터 빌드
    canvas_params = build_assignment_params(
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
    @assignments_client.update(course_id, assignment_id, { assignment: { workflow_state: 'published' } })
  end

  # Assignment 파라미터 빌드
  def build_assignment_params(assignment_params, assignment_group_id:, group_category_id:, grade_group_students_individually:, position:)
    params = {
      name: assignment_params[:name] || assignment_params[:title],
      description: assignment_params[:description],
      due_at: assignment_params[:due_at],
      unlock_at: assignment_params[:unlock_at],
      lock_at: assignment_params[:lock_at],
      points_possible: assignment_params[:points_possible],
      grading_type: assignment_params[:grading_type] || 'points',
      submission_types: parse_submission_types(assignment_params[:submission_types]),
      allowed_extensions: parse_allowed_extensions(assignment_params[:allowed_extensions]),
      allowed_attempts: assignment_params[:allowed_attempts],
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

    # Peer Review (체크박스로 선택)
    if assignment_params[:peer_reviews].to_s == 'true' || assignment_params[:peer_reviews] == true
      params[:peer_reviews] = true
      params[:automatic_peer_reviews] = assignment_params[:automatic_peer_reviews] || false
      params[:peer_review_count] = assignment_params[:peer_review_count] if assignment_params[:peer_review_count].present?
      params[:peer_reviews_due_at] = assignment_params[:peer_reviews_due_at] if assignment_params[:peer_reviews_due_at].present?
      params[:intra_group_peer_reviews] = assignment_params[:intra_group_peer_reviews] || false
      params[:anonymous_peer_reviews] = assignment_params[:anonymous_peer_reviews] || false
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
end

