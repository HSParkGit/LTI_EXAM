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

    # 역할 미리 확인 (매번 확인 안 해도 됨)
    user_role = @lti_claims[:user_role] || @lti_claims["user_role"]
    @is_instructor = user_role.to_s.downcase == "instructor"
    @canvas_user_id = @lti_claims[:canvas_user_id] || @lti_claims["canvas_user_id"]

    # 캐시용 변수
    @all_assignments_cache = nil
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

    # 코스의 모든 Assignment를 한 번에 조회 (N+1 방지)
    all_assignments = fetch_all_assignments(course_id)

    # 모든 프로젝트의 Assignment 정보 조회 (메모리에서 필터링)
    projects_with_assignments = projects.map do |project|
      # 프로젝트에 속한 assignment만 필터링
      project_assignments = filter_assignments_for_project(all_assignments, project.assignment_ids)

      # 통계 추가 (교수/학생에 따라 다름)
      project_assignments.each do |assignment|
        if @is_instructor
          add_instructor_statistics(assignment, course_id)
        else
          add_student_status(assignment, course_id)
        end
      end

      {
        id: project.id,
        name: project.name,
        published: get_published_status(project_assignments),
        assignments: project_assignments
      }
    end

    classify_projects(projects_with_assignments, is_student: !@is_instructor)
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

  # 코스의 모든 Assignment를 한 번에 조회 (캐싱)
  # @return [Array<Hash>] Assignment 목록
  def fetch_all_assignments(course_id)
    return @all_assignments_cache if @all_assignments_cache

    begin
      @all_assignments_cache = @assignments_client.list(course_id)
    rescue CanvasApi::Client::ApiError => e
      Rails.logger.error "Canvas Assignment 목록 조회 실패: #{e.message}"
      @all_assignments_cache = []
    end

    @all_assignments_cache
  end

  # 프로젝트에 속한 Assignment만 필터링
  # @param all_assignments [Array<Hash>] 전체 Assignment 목록
  # @param assignment_ids [Array<String>] 프로젝트의 Assignment ID 배열 (문자열)
  # @return [Array<Hash>] 필터링된 Assignment 목록 (deep copy)
  def filter_assignments_for_project(all_assignments, assignment_ids)
    return [] if assignment_ids.empty?

    # assignment_ids 순서 유지하면서 필터링 (deep copy로 원본 보호)
    # 주의: assignment_ids는 문자열, Canvas API의 id는 정수이므로 to_s로 비교
    assignment_ids.filter_map do |id|
      assignment = all_assignments.find { |a| a['id'].to_s == id.to_s }
      assignment&.deep_dup  # 각 프로젝트별로 통계가 다르게 추가되므로 복사
    end
  end

  # Project의 Assignment 목록 및 통계 조회 (단일 프로젝트용)
  # project_with_assignments에서 사용 (show 페이지)
  def fetch_assignments_with_statistics(project, course_id)
    return [] if project.assignment_ids.empty?

    # 캐시가 있으면 활용, 없으면 개별 조회
    if @all_assignments_cache
      assignments = filter_assignments_for_project(@all_assignments_cache, project.assignment_ids)
    else
      # show 페이지에서는 해당 프로젝트의 assignment만 필요하므로 개별 조회
      assignments = project.assignment_ids.filter_map do |assignment_id|
        begin
          @assignments_client.find(course_id, assignment_id)
        rescue CanvasApi::Client::ApiError => e
          Rails.logger.error "Canvas Assignment 조회 실패 (ID: #{assignment_id}): #{e.message}"
          nil
        end
      end
    end

    # 통계 추가
    assignments.each do |assignment|
      if @is_instructor
        add_instructor_statistics(assignment, course_id)
      else
        add_student_status(assignment, course_id)
      end
    end

    assignments
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
    return assignment unless @canvas_user_id.present?

    begin
      submission = @submissions_client.find(course_id, assignment['id'], @canvas_user_id)
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

    first_assignment = assignments.first
    # Canvas API는 workflow_state 또는 published 필드를 사용
    first_assignment['workflow_state'] == 'published' || first_assignment['published'] == true
  end
end

