# frozen_string_literal: true

module Lti
  # OIDC Login Flow를 처리하는 컨트롤러
  #
  # Canvas에서 GET /lti/login으로 요청을 보냅니다.
  # Query Parameters:
  #   - iss: Canvas 인스턴스 URL (예: https://canvas.instructure.com)
  #   - login_hint: Canvas 사용자 식별자
  #   - target_link_uri: Launch 후 이동할 URI (예: https://your-tool.com/lti/launch)
  #
  # Canvas 설정 정보:
  #   - Redirect URI: https://your-tool.com/lti/login
  #   - Initiation Login URL: https://your-tool.com/lti/login
  class LoginController < ApplicationController
    # Canvas OIDC Login Initiation 요청 처리
    def initiate
      # Canvas에서 전달된 파라미터
      iss = params[:iss]
      login_hint = params[:login_hint]
      target_link_uri = params[:target_link_uri]
      
      # 필수 파라미터 검증
      if iss.blank? || login_hint.blank? || target_link_uri.blank?
        render json: { error: "Missing required parameters" }, status: :bad_request
        return
      end
      
      # State 및 Nonce 생성
      state = SecureRandom.hex(16)
      nonce = Lti::NonceManager.generate
      
      # State를 Redis에 저장 (나중에 검증용)
      # 실제 운영에서는 state도 nonce처럼 검증해야 함
      state_key = "lti:state:#{state}"
      Rails.cache.write(state_key, {
        iss: iss,
        target_link_uri: target_link_uri,
        nonce: nonce
      }, expires_in: 10.minutes)
      
      # Canvas Authorization Endpoint URL 생성
      authorization_url = build_authorization_url(
        issuer: iss,
        login_hint: login_hint,
        target_link_uri: target_link_uri,
        state: state,
        nonce: nonce
      )
      
      # Canvas Authorization Endpoint로 리다이렉트
      redirect_to authorization_url, allow_other_host: true
    end

    private

    # Canvas Authorization Endpoint URL 생성
    # Canvas 설정:
    #   - Client ID: Canvas Developer Key에서 발급받은 값 (예: 10000000000001)
    #   - 이 값은 환경변수 LTI_CLIENT_ID로 관리
    def build_authorization_url(issuer:, login_hint:, target_link_uri:, state:, nonce:)
      client_id = ENV.fetch("LTI_CLIENT_ID") do
        raise "LTI_CLIENT_ID environment variable is required"
      end
      
      # Canvas Authorization Endpoint
      # 형식: {issuer}/api/lti/authorize_redirect
      auth_endpoint = "#{issuer}/api/lti/authorize_redirect"
      
      # OAuth 2.0 Authorization Request 파라미터
      params = {
        response_type: "id_token",
        client_id: client_id,
        redirect_uri: target_link_uri,
        login_hint: login_hint,
        state: state,
        response_mode: "form_post",
        nonce: nonce,
        prompt: "none"
      }
      
      "#{auth_endpoint}?#{params.to_query}"
    end
  end
end

