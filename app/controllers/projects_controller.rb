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
  before_action :authorize_instructor!, only: [:new, :create, :edit, :update, :destroy]
  
  # Project 목록
  def index
    @project_service = ProjectService.new(@lti_context, @lti_claims, @canvas_api)
    @projects_by_category = @project_service.projects_with_statistics
    # Canvas API로 해당 코스에서의 실제 사용자 역할 확인
    @user_role = determine_course_user_role
    
    # 코스 정보 (헤더 표시용)
    @course_title = @lti_context.context_title
  end
  
  # Project 상세
  def show
    @project_service = ProjectService.new(@lti_context, @lti_claims, @canvas_api)
    @project_data = @project_service.project_with_assignments(@project)
    
    # Canvas API로 해당 코스에서의 실제 사용자 역할 확인
    @user_role = determine_course_user_role
    # iss와 client_id로 정확한 Platform 조회 (같은 iss에서 여러 client_id 가능)
    issuer = @lti_claims[:issuer] || @lti_claims["issuer"] || @lti_claims[:iss] || @lti_claims["iss"]
    audience = @lti_claims[:audience] || @lti_claims["audience"] || @lti_claims[:aud] || @lti_claims["aud"]
    @canvas_url = LtiPlatform.find_by(iss: issuer, client_id: audience)&.actual_canvas_url
    
    # 그룹 정보 조회 (교수용 그룹 선택 드롭다운용)
    course_id = @lti_context.canvas_course_id
    if course_id.present? && @project_data[:assignments].present?
      first_assignment = @project_data[:assignments].first
      if first_assignment && first_assignment['group_category_id'].present?
        begin
          group_categories_client = CanvasApi::GroupCategoriesClient.new(@canvas_api)
          groups_response = group_categories_client.groups(first_assignment['group_category_id'])
          @groups = groups_response.is_a?(Array) ? groups_response : (groups_response['data'] || [])
        rescue => e
          Rails.logger.error "그룹 조회 실패: #{e.message}"
          @groups = []
        end
      else
        @groups = []
      end
    else
      @groups = []
    end
  end
  
  # Project 생성 폼
  def new
    @project = Project.new
    set_new_form_variables
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
    # new 액션에서 필요한 변수들 설정 (에러 발생 시 폼 재표시를 위해)
    begin
      @project ||= Project.new(project_params.except(:assignments))
    rescue
      @project ||= Project.new
    end
    set_new_form_variables
    render :new, status: :unprocessable_entity
  rescue ActionController::ParameterMissing => e
    Rails.logger.error "파라미터 에러: #{e.message}, params: #{params.inspect}"
    flash[:error] = "프로젝트 이름을 입력해주세요."
    # new 액션에서 필요한 변수들 설정 (에러 발생 시 폼 재표시를 위해)
    begin
      @project ||= Project.new(project_params.except(:assignments))
    rescue
      @project ||= Project.new
    end
    set_new_form_variables
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

    # 현재 Publish 상태 확인 (첫 번째 Assignment 기준)
    @is_published = @project_data[:assignments].present? &&
                    @project_data[:assignments].first['workflow_state'] == 'published'

    # Canvas URL (New Group Set 버튼용)
    issuer = @lti_claims[:issuer] || @lti_claims["issuer"] || @lti_claims[:iss] || @lti_claims["iss"]
    audience = @lti_claims[:audience] || @lti_claims["audience"] || @lti_claims[:aud] || @lti_claims["aud"]
    @canvas_url = LtiPlatform.find_by(iss: issuer, client_id: audience)&.actual_canvas_url
    @canvas_course_id = course_id
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

  # new 액션과 create 액션의 rescue 블록에서 공통으로 사용하는 변수 설정
  def set_new_form_variables
    course_id = @lti_context.canvas_course_id

    # Assignment Groups 조회
    assignment_groups_client = CanvasApi::AssignmentGroupsClient.new(@canvas_api)
    @assignment_groups = assignment_groups_client.list(course_id) rescue []

    # Group Categories 조회
    group_categories_client = CanvasApi::GroupCategoriesClient.new(@canvas_api)
    @group_categories = group_categories_client.list(course_id) rescue []

    # Canvas URL (New Group Set 버튼용)
    issuer = @lti_claims[:issuer] || @lti_claims["issuer"] || @lti_claims[:iss] || @lti_claims["iss"]
    audience = @lti_claims[:audience] || @lti_claims["audience"] || @lti_claims[:aud] || @lti_claims["aud"]
    @canvas_url = LtiPlatform.find_by(iss: issuer, client_id: audience)&.actual_canvas_url
    @canvas_course_id = course_id
  end
  
  # Canvas API로 코스 정보 조회 (옵션 2)
  def fetch_course_title_from_api
    return @lti_context.context_title unless @lti_context.canvas_course_id.present?
    
    begin
      courses_client = CanvasApi::CoursesClient.new(@canvas_api)
      course = courses_client.find(@lti_context.canvas_course_id)
      course['name'] || @lti_context.context_title
    rescue CanvasApi::Client::ApiError => e
      Rails.logger.error "Canvas Course 조회 실패: #{e.message}"
      @lti_context.context_title # fallback
    end
  end
  
  # LTI Claims 로드 (세션에서)
  def load_lti_claims
    @lti_claims = session[:lti_claims]
    
    # 세션 만료 확인
    if @lti_claims.blank? || session[:lti_claims_expires_at] < Time.current
      flash[:error] = '세션이 만료되었습니다. Canvas에서 LTI Tool을 다시 실행해주세요.'
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
    # JWT의 aud (client_id)를 사용하여 정확한 Platform 조회
    audience = @lti_claims[:audience] || @lti_claims["audience"] || @lti_claims[:aud] || @lti_claims["aud"]
    lti_platform = LtiPlatform.find_by(iss: issuer, client_id: audience)
    
    unless lti_platform
      flash[:error] = "Canvas Platform 정보를 찾을 수 없습니다 (iss: #{issuer}, client_id: #{audience}). Admin에서 Platform을 등록해주세요."
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

  # 교수 권한 확인
  def authorize_instructor!
    unless determine_course_user_role == :instructor
      flash[:error] = '교수만 프로젝트를 생성/수정/삭제할 수 있습니다.'
      redirect_to projects_path
    end
  end
  
  # 해당 코스에서의 사용자 역할 확인
  # LTI Claims를 우선 사용하여 불필요한 API 호출 방지
  # @return [Symbol] :instructor 또는 :student
  def determine_course_user_role
    # 1. LTI Claims에서 역할 확인 (API 호출 없이 바로 사용)
    raw_user_role = @lti_claims[:user_role] || @lti_claims["user_role"]

    if raw_user_role.present?
      case raw_user_role.to_s.downcase
      when 'instructor', 'teacher', 'administrator'
        return :instructor
      when 'student', 'learner'
        return :student
      end
    end

    # 2. user_roles 배열에서 직접 확인 (LTI 1.3 표준)
    user_roles = @lti_claims[:user_roles] || @lti_claims["user_roles"] || []
    if user_roles.any? { |role| role.to_s =~ /Instructor|Teacher|Administrator/i }
      return :instructor
    end

    # 3. 기본값: student
    :student
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
          :submission_type_select,  # UI 필드 (사용 후 제거됨)
          :attempts_type,  # UI 필드 (사용 후 제거됨)
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

