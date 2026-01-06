# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Project 생성 및 Canvas Assignment 생성
# - Canvas API를 통한 Assignment 관리
# - LTI Tool DB에 Project만 저장, Assignment는 Canvas에 저장
#
# 기술적 고려사항:
# - CanvasApi::AssignmentsClient 사용
# - Assignment ID만 Project에 저장
# - MVP: 기본 Assignment 생성만 지원
#
# 사용 시 고려사항:
# - CanvasApi::Client가 초기화되어 있어야 함
# - LtiContext가 생성되어 있어야 함
# - Canvas User ID는 LTI Claims에서 추출
class ProjectBuilder
  class ProjectCreationError < StandardError; end
  
  def initialize(lti_context:, canvas_api:, lti_user_sub:)
    @lti_context = lti_context
    @canvas_api = canvas_api
    @lti_user_sub = lti_user_sub
    @assignments_client = CanvasApi::AssignmentsClient.new(@canvas_api)
  end
  
  # Project 생성 (MVP: 이름만)
  # @param project_params [Hash] Project 파라미터
  # @return [Project] 생성된 Project
  def create_project(project_params)
    project_name = project_params[:name]
    
    unless project_name.present?
      raise ProjectCreationError, "프로젝트 이름은 필수입니다."
    end
    
    # Canvas Assignment 생성 (MVP: 1개만)
    assignment = create_assignment(project_name)
    
    # Project 생성
    project = Project.new(
      lti_context: @lti_context,
      name: project_name,
      lti_user_sub: @lti_user_sub,
      assignment_ids: [assignment['id'].to_s]
    )
    
    unless project.save
      # Assignment 롤백 (나중에 추가)
      raise ProjectCreationError, "프로젝트 생성 실패: #{project.errors.full_messages.join(', ')}"
    end
    
    project
  rescue CanvasApi::Client::ApiError => e
    Rails.logger.error "Canvas Assignment 생성 실패: #{e.message}"
    raise ProjectCreationError, "과제 생성에 실패했습니다: #{e.message}"
  end
  
  private
  
  # Canvas Assignment 생성
  # @param project_name [String] 프로젝트 이름
  # @return [Hash] 생성된 Assignment 정보
  def create_assignment(project_name)
    # Canvas 실제 Course ID 사용 (Custom Parameters에서 받은 값)
    course_id = @lti_context.canvas_course_id
    
    unless course_id.present?
      raise ProjectCreationError, "Canvas Course ID를 찾을 수 없습니다. Canvas Developer Key의 Custom Fields에 'course_id=$Canvas.course.id'를 설정해주세요."
    end
    
    assignment_params = {
      name: project_name,
      submission_types: ['online_url', 'online_upload'],
      workflow_state: 'unpublished',
      # MVP: 기본 설정만
    }
    
    @assignments_client.create(course_id, assignment_params)
  end
end

