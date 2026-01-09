# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Project 목록 조회 및 통계 제공
# - Canvas API를 통한 Assignment/Submission 정보 조회
# - 프로젝트 분류: Current / Upcoming / Past / Unpublished
# - 교수/학생별 다른 통계 제공
#
# 기술적 고려사항:
# - CanvasApi::AssignmentsClient, SubmissionsClient 사용
# - Canvas API 호출 최소화 (나중에 캐싱 추가)
# - N+1 쿼리 방지
#
# 사용 시 고려사항:
# - CanvasApi::Client가 초기화되어 있어야 함
# - LtiContext와 current_user, user_role 필요함
class ProjectService
  class ProjectServiceError < StandardError; end

  def initialize(lti_context, lti_claims, canvas_api)
    @lti_context = lti_context
    @lti_claims = lti_claims
    @canvas_api = canvas_api
    @assignments_client = CanvasApi::AssignmentsClient.new(@canvas_api)
    @submissions_client = CanvasApi::SubmissionsClient.new(@canvas_api)
  end

  # Project 목록 조회 (기본)
  # @return [Array<Project>] Project 목록
  def projects
    @lti_context.projects.order(created_at: :desc)
  end

  # 제출 통계가 포함된 프로젝트 목록 조회 및 분류
  # @return [Hash] 분류된 프로젝트 목록
  #   { current: [...], upcoming: [...], past: [...], unpublished: [...] }
  def projects_with_statistics
    course_id = @lti_context.canvas_course_id

    unless course_id.present?
      Rails.logger.error "Canvas Course ID를 찾을 수 없습니다. LtiContext ID: #{@lti_context.id}"
      return { current: [], upcoming: [], past: [], unpublished: [] }
    end

    # 모든 프로젝트의 Assignment 정보 조회
    projects_with_assignments = projects.map do |project|
      assignments = fetch_assignments_with_statistics(project, course_id)

      {
        id: project.id,
        name: project.name,
        published: get_published_status(assignments),
        assignments: assignments
      }
    end

    # 프로젝트 분류
    classify_projects(projects_with_assignments)
  end

  # Project 상세 조회 (Assignment 정보 포함)
  # @param project [Project] Project 객체
  # @return [Hash] Project 상세 정보
  def project_with_assignments(project)
    course_id = @lti_context.canvas_course_id

    unless course_id.present?
      Rails.logger.error "Canvas Course ID를 찾을 수 없습니다. LtiContext ID: #{@lti_context.id}"
      return {
        id: project.id,
        name: project.name,
        assignments: []
      }
    end

    assignments = fetch_assignments_with_statistics(project, course_id)

    {
      id: project.id,
      name: project.name,
      assignments: assignments
    }
  end

  private

  # Project의 Assignment 목록 및 통계 조회
  def fetch_assignments_with_statistics(project, course_id)
    project.assignment_ids.map do |assignment_id|
      begin
        assignment = @assignments_client.find(course_id, assignment_id)

        # 교수/학생에 따라 다른 통계 추가
        if @lti_claims[:user_role] == :instructor
          add_instructor_statistics(assignment, course_id)
        else
          add_student_status(assignment, course_id)
        end

        assignment
      rescue CanvasApi::Client::ApiError => e
        Rails.logger.error "Canvas Assignment 조회 실패: #{e.message}"
        nil
      end
    end.compact
  end

  # 교수용: Submission 통계 추가
  def add_instructor_statistics(assignment, course_id)
    begin
      stats = @submissions_client.statistics(course_id, assignment['id'])
      assignment.merge!(stats)
    rescue CanvasApi::Client::ApiError => e
      Rails.logger.error "Submission 통계 조회 실패: #{e.message}"
      assignment.merge!(
        submitted_count: 0,
        unsubmitted_count: 0,
        graded_count: 0,
        grading_required: 0
      )
    end
  end

  # 학생용: 본인 제출 여부 추가
  def add_student_status(assignment, course_id)
    canvas_user_id = @lti_claims[:canvas_user_id]

    return assignment unless canvas_user_id.present?

    begin
      submission = @submissions_client.find(course_id, assignment['id'], canvas_user_id)
      assignment['is_submitted'] = submission['submitted_at'].present?
    rescue CanvasApi::Client::ApiError => e
      Rails.logger.error "Submission 조회 실패: #{e.message}"
      assignment['is_submitted'] = false
    end

    assignment
  end

  # 프로젝트 분류
  def classify_projects(projects)
    current_date = Time.current

    {
      current: projects.select { |p| has_active_step?(p, current_date) },
      upcoming: projects.select { |p| all_steps_not_started?(p, current_date) },
      past: projects.select { |p| all_steps_completed?(p, current_date) },
      unpublished: projects.select { |p| !p[:published] }
    }
  end

  # 프로젝트에 진행 중인 STEP이 있는지 확인
  def has_active_step?(project, current_date)
    return false if project[:assignments].empty?

    project[:assignments].any? do |assignment|
      unlock_at = assignment['unlock_at'] ? Time.parse(assignment['unlock_at']) : nil
      due_at = assignment['due_at'] ? Time.parse(assignment['due_at']) : nil

      (unlock_at.nil? || current_date >= unlock_at) &&
      (due_at.nil? || current_date <= due_at)
    end
  end

  # 모든 STEP이 시작 전인지 확인
  def all_steps_not_started?(project, current_date)
    return false if project[:assignments].empty?
    return false unless project[:published] # unpublished는 제외

    project[:assignments].all? do |assignment|
      unlock_at = assignment['unlock_at'] ? Time.parse(assignment['unlock_at']) : nil
      unlock_at && current_date < unlock_at
    end
  end

  # 모든 STEP이 완료되었는지 확인
  def all_steps_completed?(project, current_date)
    return false if project[:assignments].empty?
    return false unless project[:published] # unpublished는 제외

    project[:assignments].all? do |assignment|
      due_at = assignment['due_at'] ? Time.parse(assignment['due_at']) : nil
      due_at && current_date > due_at
    end
  end

  # Published 상태 확인 (첫 번째 Assignment 기준)
  def get_published_status(assignments)
    return false if assignments.empty?
    assignments.first&.dig('workflow_state') == 'published'
  end
end

