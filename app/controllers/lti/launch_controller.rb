# frozen_string_literal: true

module Lti
  # LTI Launch를 처리하는 컨트롤러
  #
  # Canvas에서 POST /lti/launch로 id_token을 전달합니다.
  # Form Data:
  #   - id_token: JWT 형식의 LTI Launch 메시지
  #   - state: OIDC Login에서 생성한 state
  #
  # Canvas 설정 정보:
  #   - Redirect URI: https://your-tool.com/lti/launch
  #   - Target Link URI: https://your-tool.com/lti/launch
  class LaunchController < BaseController
    # LTI Launch 요청 처리
    def handle
      # Canvas가 에러를 반환한 경우 처리
      if params[:error].present?
        error_description = params[:error_description] || params[:error]
        Rails.logger.error "Canvas returned error: #{params[:error]} - #{error_description}"
        render json: { 
          error: params[:error], 
          error_description: error_description,
          state: params[:state]
        }, status: :bad_request
        return
      end
      
      id_token = params[:id_token]
      state = params[:state]
      
      # 필수 파라미터 검증
      if id_token.blank?
        Rails.logger.error "Missing id_token in launch request. Params: #{params.except(:authenticity_token, :utf8, :id_token).inspect}"
        render json: { error: "Missing id_token" }, status: :bad_request
        return
      end
      
      # State 검증 (Redis에서 조회)
      state_data = validate_state(state)
      unless state_data
        Rails.logger.error "Invalid or expired state: #{state}"
        render json: { error: "Invalid or expired state" }, status: :bad_request
        return
      end
      
      # JWT 검증
      # iss와 client_id로 정확한 Platform 조회 (같은 iss에 여러 Tool이 있을 수 있음)
      expected_client_id = Lti::PlatformConfig.client_id_for(state_data[:iss], state_data[:client_id])
      
      begin
        payload = Lti::JwtVerifier.verify(
          id_token,
          expected_iss: state_data[:iss],
          expected_aud: expected_client_id,
          nonce: state_data[:nonce]
        )
      rescue Lti::JwtVerifier::VerificationError => e
        Rails.logger.error "JWT verification failed: #{e.message}"
        render json: { error: "JWT verification failed: #{e.message}" }, status: :unauthorized
        return
      end
      
      # 디버깅: 실제 JWT payload 확인 (개발 환경에서만)
      if Rails.env.development?
        Rails.logger.info "=== JWT Payload (개발용) ==="
        Rails.logger.info payload.to_json
        Rails.logger.info "============================"
      end
      
      # LTI Claims 추출
      @lti_claims = extract_lti_claims(payload)
      
      # LtiContext 생성 또는 조회
      issuer = @lti_claims[:issuer] || @lti_claims["issuer"] || @lti_claims[:iss] || @lti_claims["iss"]
      # JWT의 aud (client_id)를 사용하여 정확한 Platform 조회
      # 같은 Canvas 인스턴스(iss)에서 여러 Developer Key를 사용할 수 있음
      audience = @lti_claims[:audience] || @lti_claims["audience"] || @lti_claims[:aud] || @lti_claims["aud"]
      lti_platform = LtiPlatform.find_by(iss: issuer, client_id: audience)
      unless lti_platform
        Rails.logger.error "LTI Platform을 찾을 수 없습니다: iss=#{issuer}, client_id=#{audience}"
        render json: { error: "LTI Platform을 찾을 수 없습니다 (iss: #{issuer}, client_id: #{audience})" }, status: :bad_request
        return
      end
      
      lti_context = LtiContext.find_or_create_by(
        context_id: @lti_claims[:course_id] || @lti_claims["course_id"],
        platform_iss: issuer
      ) do |context|
        context.context_type = @lti_claims[:context_type] || @lti_claims["context_type"] || 'Course'
        context.context_title = @lti_claims[:context_title] || @lti_claims["context_title"]
        context.context_label = @lti_claims[:context_label] || @lti_claims["context_label"]
        context.canvas_url = lti_platform.actual_canvas_url
        context.deployment_id = @lti_claims[:deployment_id] || @lti_claims["deployment_id"]
      end

      # 기존 레코드의 코스 정보 최신화 (매 launch마다)
      updates = {}
      context_title = @lti_claims[:context_title] || @lti_claims["context_title"]
      context_label = @lti_claims[:context_label] || @lti_claims["context_label"]
      canvas_course_id = (@lti_claims[:canvas_course_id] || @lti_claims["canvas_course_id"])&.to_i

      updates[:context_title] = context_title if context_title.present? && lti_context.context_title != context_title
      updates[:context_label] = context_label if context_label.present? && lti_context.context_label != context_label
      updates[:canvas_course_id] = canvas_course_id if canvas_course_id.present? && canvas_course_id > 0 && lti_context.canvas_course_id != canvas_course_id

      if updates.any?
        lti_context.update(updates)
        Rails.logger.info "LtiContext 업데이트 (#{lti_context.id}): #{updates.keys.join(', ')}"
      end
      
      # 세션에 LTI Claims 저장 (HashWithIndifferentAccess로 Symbol/String 키 모두 지원)
      session[:lti_claims] = @lti_claims.with_indifferent_access
      session[:lti_claims_expires_at] = 1.hour.from_now
      session[:lti_context_id] = lti_context.id

      # 서드파티 쿠키 차단 대비: 서버사이드 토큰으로도 저장
      # Safari, Chrome 시크릿 등에서 iframe 내 세션 쿠키가 차단될 때 사용
      @lti_token = SecureRandom.hex(32)
      Rails.cache.write(
        "lti_token:#{@lti_token}",
        {
          lti_claims: @lti_claims.with_indifferent_access,
          lti_claims_expires_at: 1.hour.from_now,
          lti_context_id: lti_context.id
        },
        expires_in: 1.hour
      )
      
      # 디버깅: 세션 저장 확인
      Rails.logger.info "=== LTI Launch 성공 ==="
      Rails.logger.info "Session ID: #{session.id}"
      Rails.logger.info "LTI Claims 저장됨: #{session[:lti_claims].present?}"
      Rails.logger.info "LtiContext ID: #{lti_context.id}"
      Rails.logger.info "======================"
      
      # Rails 세션은 자동으로 저장되므로 별도 save 호출 불필요
      # Tool 파라미터에 따라 분기
      redirect_to_tool
    end

    # Tool 파라미터에 따라 적절한 경로로 리다이렉트
    def redirect_to_tool
      tool = params[:tool]&.downcase

      case tool
      when 'attendance'
        redirect_to attendance_index_path(lti_token: @lti_token)
      when 'projects', nil
        redirect_to projects_path(lti_token: @lti_token)
      else
        Rails.logger.warn "Unknown tool requested: #{tool}, redirecting to projects"
        redirect_to projects_path(lti_token: @lti_token)
      end
    end

    private

    # State 검증 및 데이터 조회
    def validate_state(state)
      return nil if state.blank?
      
      state_key = "lti:state:#{state}"
      state_data = Rails.cache.read(state_key)
      
      # State 소비 (일회성 사용)
      Rails.cache.delete(state_key) if state_data
      
      state_data
    end

    # 이 메서드는 더 이상 사용되지 않음 (PlatformConfig로 대체)
    # 하위 호환을 위해 유지하지만, 실제로는 사용되지 않음
    # def client_id
    #   @client_id ||= ENV.fetch("LTI_CLIENT_ID") do
    #     raise "LTI_CLIENT_ID environment variable is required"
    #   end
    # end

    # LTI Claims 추출
    # LTI 1.3 Core Claims에서 사용 가능한 모든 정보 추출
    # 참고: https://www.imsglobal.org/spec/lti/v1p3/
    def extract_lti_claims(payload)
      # Context 정보 (코스 정보)
      context = payload["https://purl.imsglobal.org/spec/lti/claim/context"] || {}
      
      # Resource Link 정보 (과제/모듈 정보 - 선택적)
      resource_link = payload["https://purl.imsglobal.org/spec/lti/claim/resource_link"] || {}
      
      # Roles 정보
      roles = payload["https://purl.imsglobal.org/spec/lti/claim/roles"] || []
      
      # Role에서 Instructor/Student 판단
      user_role = determine_user_role(roles)
      
      # Deployment 정보 (LTI 배포 ID - 선택적)
      deployment_id = payload["https://purl.imsglobal.org/spec/lti/claim/deployment_id"]
      
      # Message Type (LTI 메시지 타입)
      message_type = payload["https://purl.imsglobal.org/spec/lti/claim/message_type"]
      
      # Version
      version = payload["https://purl.imsglobal.org/spec/lti/claim/version"]
      
      # Target Link URI
      target_link_uri = payload["https://purl.imsglobal.org/spec/lti/claim/target_link_uri"]
      
      # Custom Parameters (Canvas Developer Key에서 설정한 커스텀 필드)
      # 예: course_id=$Canvas.course.id, user_id=$Canvas.user.id
      custom_params = payload["https://purl.imsglobal.org/spec/lti/claim/custom"] || {}
      
      # Canvas 특정 클레임 (있을 수도, 없을 수도 있음)
      canvas_user_id_claim = payload["https://canvas.instructure.com/lti/user_id"]
      canvas_course_id_claim = payload["https://canvas.instructure.com/lti/course_id"]
      
      # Custom Parameters에서 추출 (우선순위 높음)
      # Canvas Developer Key의 Custom Fields에서 설정한 값
      custom_course_id = custom_params["course_id"] || custom_params[:course_id]
      custom_user_id = custom_params["user_id"] || custom_params[:user_id]
      
      {
        # Context (코스) 정보
        course_id: context["id"],
        context_title: context["title"],
        context_type: context["type"], # Course, Group 등
        context_label: context["label"],
        
        # Resource Link (과제/모듈) 정보 - 선택적
        resource_link_id: resource_link["id"],
        resource_link_title: resource_link["title"],
        resource_link_description: resource_link["description"],
        
        # 사용자 정보
        user_sub: payload["sub"], # Canvas 사용자 고유 ID
        user_name: payload["name"] || payload["given_name"] || "Unknown",
        user_given_name: payload["given_name"],
        user_family_name: payload["family_name"],
        user_email: payload["email"], # 이메일 (Canvas가 제공하는 경우)
        user_picture: payload["picture"], # 프로필 사진 URL (선택적)
        
        # 역할 정보
        user_role: user_role,
        user_roles: roles, # 전체 역할 배열
        
        # LTI 정보
        deployment_id: deployment_id, # LTI 배포 ID
        message_type: message_type, # LtiResourceLinkRequest 등
        version: version, # "1.3.0"
        target_link_uri: target_link_uri, # Target Link URI
        
        # 표준 OIDC Claims
        issuer: payload["iss"], # Canvas 인스턴스 URL
        audience: payload["aud"], # Client ID
        issued_at: payload["iat"] ? Time.at(payload["iat"]) : nil, # 발급 시간
        expiration: payload["exp"] ? Time.at(payload["exp"]) : nil, # 만료 시간
        
        # Canvas 내부 ID (우선순위: Custom Parameters > Canvas 특정 클레임)
        # Custom Parameters는 Canvas Developer Key에서 설정 가능
        canvas_user_id: custom_user_id || canvas_user_id_claim, # Canvas 내부 사용자 ID
        canvas_course_id: custom_course_id || canvas_course_id_claim, # Canvas 내부 코스 ID
        canvas_account_id: payload["https://canvas.instructure.com/lti/account_id"], # Canvas 계정 ID
        canvas_workflow_state: payload["https://canvas.instructure.com/lti/workflow_state"], # 코스 상태 (active 등)
        
        # Custom Parameters 전체 (디버깅 및 확장용)
        custom_params: custom_params,

        # 출결용 학생 식별자 (Canvas Developer Key Custom Fields에서 설정)
        # VOD (Panopto): custom_canvas_user_login_id = $Canvas.user.loginId
        # LIVE (Zoom): email (위에서 이미 추출)
        custom_canvas_user_login_id: custom_params["canvas_user_login_id"] || custom_params[:canvas_user_login_id],
        custom_canvas_user_id: custom_params["canvas_user_id"] || custom_params[:canvas_user_id] || custom_user_id,

        # Canvas 사용자 언어 설정
        locale: payload["locale"]
      }
    end

    # Canvas 역할에서 사용자 역할 판단
    def determine_user_role(roles)
      role_uris = roles.is_a?(Array) ? roles : [roles]
      
      # Instructor 역할 확인
      instructor_patterns = [
        /Instructor$/,
        /Teacher$/,
        /Administrator$/
      ]
      
      if role_uris.any? { |role| instructor_patterns.any? { |pattern| role.to_s.match?(pattern) } }
        :instructor
      else
        :student
      end
    end
  end
end

