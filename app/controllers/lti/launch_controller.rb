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
      id_token = params[:id_token]
      state = params[:state]
      
      # 필수 파라미터 검증
      if id_token.blank?
        render json: { error: "Missing id_token" }, status: :bad_request
        return
      end
      
      # State 검증 (Redis에서 조회)
      state_data = validate_state(state)
      unless state_data
        render json: { error: "Invalid or expired state" }, status: :bad_request
        return
      end
      
      # JWT 검증
      # iss에 해당하는 client_id 조회 (여러 Canvas 인스턴스 지원)
      expected_client_id = Lti::PlatformConfig.client_id_for(state_data[:iss])
      
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
      
      # LTI Claims 추출
      lti_claims = extract_lti_claims(payload)
      
      # Launch 성공 - 화면 렌더링
      @course_id = lti_claims[:course_id]
      @user_role = lti_claims[:user_role]
      @user_sub = lti_claims[:user_sub]
      @context_title = lti_claims[:context_title]
      @user_name = lti_claims[:user_name]
      
      render :handle
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
    # LTI 1.3 Core Claims:
    #   - https://purl.imsglobal.org/spec/lti/claim/context: 코스 정보
    #   - https://purl.imsglobal.org/spec/lti/claim/roles: 사용자 역할
    #   - sub: 사용자 식별자
    def extract_lti_claims(payload)
      context = payload["https://purl.imsglobal.org/spec/lti/claim/context"] || {}
      roles = payload["https://purl.imsglobal.org/spec/lti/claim/roles"] || []
      
      # Role에서 Instructor/Student 판단
      # Canvas 역할: http://purl.imsglobal.org/vocab/lis/v2/institution/person#Instructor
      #              http://purl.imsglobal.org/vocab/lis/v2/institution/person#Learner
      user_role = determine_user_role(roles)
      
      {
        course_id: context["id"],
        context_title: context["title"],
        user_role: user_role,
        user_sub: payload["sub"],
        user_name: payload["name"] || payload["given_name"] || "Unknown"
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

