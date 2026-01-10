# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Project CRUD 컨트롤러
# - LTI Claims를 세션에서 로드
# - Canvas API를 통한 Assignment 관리
#
# 기술적 고려사항:
# - 세션 만료 시 LTI Launch 재요청 안내
# - Canvas API Token 생성 및 캐싱
# - 에러 처리 (기본만, MVP)
#
# 사용 시 고려사항:
# - LTI Launch 후 세션에 LTI Claims가 저장되어 있어야 함
# - Canvas API Token은 자동 생성
class ProjectsController < ApplicationController
  before_action :load_lti_claims
  before_action :set_lti_context
  before_action :set_canvas_api_client
  before_action :set_project, only: [:show, :edit, :update, :destroy]
  
  # Project 목록
  def index
    @project_service = ProjectService.new(@lti_context, @lti_claims, @canvas_api)
    @projects_by_category = @project_service.projects_with_statistics
    @user_role = @lti_claims[:user_role] || @lti_claims["user_role"]
  end
  
  # Project 상세
  def show
    @project_service = ProjectService.new(@lti_context, @lti_claims, @canvas_api)
    @project_data = @project_service.project_with_assignments(@project)
    @user_role = @lti_claims[:user_role] || @lti_claims["user_role"]
    @canvas_url = LtiPlatform.find_by(iss: @lti_claims[:iss] || @lti_claims["iss"])&.actual_canvas_url
  end
  
  # Project 생성 폼
  def new
    @project = Project.new
    course_id = @lti_context.canvas_course_id
    
    # Assignment Groups 조회
    assignment_groups_client = CanvasApi::AssignmentGroupsClient.new(@canvas_api)
    @assignment_groups = assignment_groups_client.list(course_id) rescue []
    
    # Group Categories 조회
    group_categories_client = CanvasApi::GroupCategoriesClient.new(@canvas_api)
    @group_categories = group_categories_client.list(course_id) rescue []
  end
  
  # Project 생성
  def create
    project_builder = ProjectBuilder.new(
      lti_context: @lti_context,
      canvas_api: @canvas_api,
      lti_user_sub: @lti_claims[:user_sub] || @lti_claims["user_sub"]
    )
    
    @project = project_builder.create_project(project_params)
    
    redirect_to project_path(@project), notice: '프로젝트가 생성되었습니다.'
  rescue ProjectBuilder::ProjectCreationError => e
    flash[:error] = e.message
    render :new, status: :unprocessable_entity
  rescue ActionController::ParameterMissing => e
    Rails.logger.error "파라미터 에러: #{e.message}, params: #{params.inspect}"
    flash[:error] = "프로젝트 이름을 입력해주세요."
    render :new, status: :unprocessable_entity
  end
  
  # Project 수정 폼
  def edit
    course_id = @lti_context.canvas_course_id
    
    # Assignment Groups 조회
    assignment_groups_client = CanvasApi::AssignmentGroupsClient.new(@canvas_api)
    @assignment_groups = assignment_groups_client.list(course_id) rescue []
    
    # Group Categories 조회
    group_categories_client = CanvasApi::GroupCategoriesClient.new(@canvas_api)
    @group_categories = group_categories_client.list(course_id) rescue []
    
    # 기존 Assignment 정보 조회
    @project_service = ProjectService.new(@lti_context, @lti_claims, @canvas_api)
    @project_data = @project_service.project_with_assignments(@project)
  end
  
  # Project 수정
  def update
    project_builder = ProjectBuilder.new(
      lti_context: @lti_context,
      canvas_api: @canvas_api,
      lti_user_sub: @lti_claims[:user_sub] || @lti_claims["user_sub"],
      project: @project
    )
    
    @project = project_builder.update_project(project_params)
    
    redirect_to project_path(@project), notice: '프로젝트가 수정되었습니다.'
  rescue ProjectBuilder::ProjectCreationError => e
    flash[:error] = e.message
    render :edit, status: :unprocessable_entity
  end
  
  # Project 삭제
  def destroy
    # MVP: Assignment 삭제는 나중에 추가
    @project.destroy
    redirect_to projects_path, notice: '프로젝트가 삭제되었습니다.'
  end
  
  private
  
  # LTI Claims 로드 (세션에서)
  def load_lti_claims
    @lti_claims = session[:lti_claims]
    
    # 디버깅: 세션 상태 확인
    Rails.logger.info "=== ProjectsController 세션 확인 ==="
    Rails.logger.info "Session ID: #{session.id}"
    Rails.logger.info "LTI Claims 존재: #{@lti_claims.present?}"
    Rails.logger.info "LTI Claims: #{@lti_claims.inspect}" if @lti_claims.present?
    Rails.logger.info "세션 만료 시간: #{session[:lti_claims_expires_at]}"
    Rails.logger.info "현재 시간: #{Time.current}"
    Rails.logger.info "================================"
    
    # 세션 만료 확인
    if @lti_claims.blank? || session[:lti_claims_expires_at] < Time.current
      Rails.logger.error "세션이 없거나 만료됨!"
      flash[:error] = '세션이 만료되었습니다. Canvas에서 LTI Tool을 다시 실행해주세요.'
      # 세션이 없으면 Admin 페이지로 리다이렉트 (설정 확인용)
      redirect_to admin_lti_platforms_path
      return
    end
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
    # 세션에 저장된 해시는 문자열 키로 변환될 수 있으므로 둘 다 확인
    issuer = @lti_claims[:issuer] || @lti_claims["issuer"] || @lti_claims[:iss] || @lti_claims["iss"]
    lti_platform = LtiPlatform.find_by(iss: issuer)
    
    unless lti_platform
      flash[:error] = 'Canvas Platform 정보를 찾을 수 없습니다. Admin에서 Platform을 등록해주세요.'
      redirect_to admin_lti_platforms_path
      return
    end
    
    # Canvas API Access Token 생성
    access_token = Lti::CanvasApiTokenGenerator.generate(lti_platform)
    
    # Canvas API Client 생성
    @canvas_api = CanvasApi::Client.new(
      lti_platform.actual_canvas_url,
      access_token
    )
  rescue Lti::CanvasApiTokenGenerator::TokenGenerationError => e
    flash[:error] = "Canvas API 인증에 실패했습니다: #{e.message}. Client Secret을 확인해주세요."
    redirect_to admin_lti_platforms_path
  end
  
  # Project 설정
  def set_project
    @project = @lti_context.projects.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = '프로젝트를 찾을 수 없습니다.'
    redirect_to projects_path
  end
  
  # Project 파라미터
  def project_params
    if params[:project].present?
      params.require(:project).permit(
        :name,
        :assignment_group_id,
        :group_category_id,
        :grade_group_students_individually,
        :publish,
        assignments: [
          :id,
          :name,
          :description,
          :due_at,
          :unlock_at,
          :lock_at,
          :points_possible,
          :submission_types,
          :allowed_extensions,
          :allowed_attempts,
          :grading_type,
          :peer_reviews,
          :automatic_peer_reviews,
          :peer_review_count,
          :peer_reviews_due_at,
          :intra_group_peer_reviews,
          :anonymous_peer_reviews,
          :_destroy
        ]
      )
    else
      # 폼에서 project 키 없이 전송된 경우 (fallback)
      { name: params[:name] }
    end
  end
end

