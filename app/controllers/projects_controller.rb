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
    @project_service = ProjectService.new(@lti_context, @canvas_api)
    @projects = @project_service.projects
  end
  
  # Project 상세
  def show
    @project_service = ProjectService.new(@lti_context, @canvas_api)
    @project_data = @project_service.project_with_assignments(@project)
  end
  
  # Project 생성 폼
  def new
    @project = Project.new
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
  end
  
  # Project 수정
  def update
    if @project.update(project_params)
      redirect_to project_path(@project), notice: '프로젝트가 수정되었습니다.'
    else
      flash[:error] = "프로젝트 수정 실패: #{@project.errors.full_messages.join(', ')}"
      render :edit, status: :unprocessable_entity
    end
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
    # project 키가 있으면 사용, 없으면 직접 name 파라미터 사용
    if params[:project].present?
      params.require(:project).permit(:name)
    else
      # 폼에서 project 키 없이 전송된 경우 (fallback)
      { name: params[:name] }
    end
  end
end

