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

    # 프로젝트 분류 (Canvas 로직: 학생은 Unpublished 프로젝트를 볼 수 없음)
    user_role = @lti_claims[:user_role] || @lti_claims["user_role"]
    user_role_str = user_role.to_s.downcase
    is_student = user_role_str != "instructor"
    
    classify_projects(projects_with_assignments, is_student: is_student)
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
    return [] if project.assignment_ids.empty?
    
    project.assignment_ids.map do |assignment_id|
      begin
        assignment = @assignments_client.find(course_id, assignment_id)

        # 교수/학생에 따라 다른 통계 추가
        user_role = @lti_claims[:user_role] || @lti_claims["user_role"]
        user_role_str = user_role.to_s.downcase
        if user_role_str == "instructor"
          add_instructor_statistics(assignment, course_id)
        else
          add_student_status(assignment, course_id)
        end

        assignment
      rescue CanvasApi::Client::ApiError => e
        Rails.logger.error "Canvas Assignment 조회 실패 (ID: #{assignment_id}): #{e.message}"
        nil
      rescue => e
        Rails.logger.error "예상치 못한 에러 (ID: #{assignment_id}): #{e.class} - #{e.message}"
        nil
      end
    end.compact
  end

  # 교수용: Submission 통계 추가
  def add_instructor_statistics(assignment, course_id)
    begin
      stats = @submissions_client.statistics(course_id, assignment['id'])
      assignment.merge!(stats)
      
      # 그룹 멤버별 제출 상태 조회 (Evaluations 섹션용)
      # TODO: 그룹 정보와 매칭하여 실제 그룹 멤버만 표시하도록 개선 필요
      begin
        submissions = @submissions_client.list(course_id, assignment['id'], include: ['user'])
        assignment['group_submissions'] = submissions.map do |submission|
          {
            submission: submission,
            user_name: submission['user'] ? "#{submission['user']['name']}" : "Student #{submission['user_id']}"
          }
        end
      rescue => e
        Rails.logger.error "그룹 멤버 제출 상태 조회 실패: #{e.message}"
        assignment['group_submissions'] = []
      end
    rescue CanvasApi::Client::ApiError => e
      Rails.logger.error "Submission 통계 조회 실패: #{e.message}"
      assignment.merge!(
        submitted_count: 0,
        unsubmitted_count: 0,
        graded_count: 0,
        grading_required: 0,
        group_submissions: []
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
  # Canvas hy_projects 로직과 동일하게 구현:
  # 1. Unpublished 프로젝트는 unpublished에만 포함 (최우선)
  # 2. Published 프로젝트만 current/upcoming/past에 포함
  # 3. Current/Upcoming/Past는 상호 배타적 (하나에만 포함)
  # 4. 학생은 Unpublished 프로젝트를 볼 수 없음
  # @param projects [Array] 프로젝트 목록
  # @param is_student [Boolean] 학생 여부 (기본값: false)
  # @return [Hash] 분류된 프로젝트 목록
  def classify_projects(projects, is_student: false)
    current_date = Time.current
    
    # 1. Published/Unpublished 분리 (Canvas 로직: published !== false)
    published_projects = projects.select { |p| p[:published] != false }
    unpublished_projects = projects.select { |p| p[:published] == false }
    
    # 2. Published 프로젝트만으로 current/upcoming/past 분류
    upcoming_projects = published_projects.select { |p| all_steps_not_started?(p, current_date) }
    past_projects = published_projects.select { |p| all_steps_completed?(p, current_date) }
    
    # 3. Current: Published이면서 upcoming도 past도 아닌 것
    current_projects = published_projects.reject do |p|
      all_steps_not_started?(p, current_date) || all_steps_completed?(p, current_date)
    end
    
    # 4. Unpublished 프로젝트는 별도 관리 (학생은 볼 수 없음 - Canvas 로직)
    visible_unpublished = is_student ? [] : unpublished_projects
    
    {
      current: current_projects,
      upcoming: upcoming_projects,
      past: past_projects,
      unpublished: visible_unpublished
    }
  end

  # 모든 STEP이 시작 전인지 확인 (Published 프로젝트 전용)
  def all_steps_not_started?(project, current_date)
    return false if project[:assignments].empty?

    project[:assignments].all? do |assignment|
      unlock_at = assignment['unlock_at'] ? Time.parse(assignment['unlock_at']) : nil
      unlock_at && current_date < unlock_at
    end
  end

  # 모든 STEP이 완료되었는지 확인 (Published 프로젝트 전용)
  def all_steps_completed?(project, current_date)
    return false if project[:assignments].empty?

    project[:assignments].all? do |assignment|
      due_at = assignment['due_at'] ? Time.parse(assignment['due_at']) : nil
      due_at && current_date > due_at
    end
  end

  # Published 상태 확인 (첫 번째 Assignment 기준)
  # 주의: assignments가 비어있으면 false 반환 (unpublished로 분류됨)
  def get_published_status(assignments)
    return false if assignments.empty?

    assignments.first['workflow_state'] == 'published'
  end
end

