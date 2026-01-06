# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Project 목록 조회 및 통계 제공
# - Canvas API를 통한 Assignment 정보 조회
# - MVP: 기본 조회만 지원
#
# 기술적 고려사항:
# - CanvasApi::AssignmentsClient 사용
# - Canvas API 호출 최소화 (나중에 캐싱 추가)
#
# 사용 시 고려사항:
# - CanvasApi::Client가 초기화되어 있어야 함
# - LtiContext가 필요함
class ProjectService
  class ProjectServiceError < StandardError; end
  
  def initialize(lti_context, canvas_api)
    @lti_context = lti_context
    @canvas_api = canvas_api
    @assignments_client = CanvasApi::AssignmentsClient.new(@canvas_api)
  end
  
  # Project 목록 조회 (MVP: 기본 정보만)
  # @return [Array<Project>] Project 목록
  def projects
    @lti_context.projects.order(created_at: :desc)
  end
  
  # Project 상세 조회 (Assignment 정보 포함)
  # @param project [Project] Project 객체
  # @return [Hash] Project 상세 정보
  def project_with_assignments(project)
    # Canvas 실제 Course ID 사용 (Custom Parameters에서 받은 값)
    course_id = @lti_context.canvas_course_id
    
    unless course_id.present?
      Rails.logger.error "Canvas Course ID를 찾을 수 없습니다. LtiContext ID: #{@lti_context.id}"
      return {
        id: project.id,
        name: project.name,
        created_at: project.created_at,
        updated_at: project.updated_at,
        assignments: []
      }
    end
    
    # Canvas API로 Assignment 정보 조회
    assignments = project.assignment_ids.map do |assignment_id|
      begin
        @assignments_client.find(course_id, assignment_id)
      rescue CanvasApi::Client::ApiError => e
        Rails.logger.error "Canvas Assignment 조회 실패: #{e.message}"
        nil
      end
    end.compact
    
    {
      id: project.id,
      name: project.name,
      created_at: project.created_at,
      updated_at: project.updated_at,
      assignments: assignments
    }
  end
end

