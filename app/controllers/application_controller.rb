class ApplicationController < ActionController::Base
  # 서드파티 쿠키 차단 대비: 토큰으로 세션 복원 (load_lti_claims보다 먼저 실행)
  before_action :restore_lti_session_from_token

  # Canvas iframe에서 표시 가능하도록 X-Frame-Options 제거 (전역)
  after_action :allow_iframe, unless: :admin_controller?

  private

  # Safari, Chrome 시크릿 등에서 iframe 내 세션 쿠키가 차단될 때
  # URL 파라미터(?lti_token=xxx) 또는 세션에 저장된 토큰으로 LTI 데이터 복원
  def restore_lti_session_from_token
    token = params[:lti_token] || session[:lti_token]
    return if token.blank?

    # 세션에 유효한 claims가 이미 있으면 스킵
    if session[:lti_claims].present? && session[:lti_claims_expires_at].present? &&
       session[:lti_claims_expires_at] > Time.current
      session[:lti_token] ||= token
      return
    end

    # 캐시에서 토큰으로 LTI 데이터 복원
    cached_data = Rails.cache.read("lti_token:#{token}")
    return if cached_data.blank?

    session[:lti_claims] = cached_data[:lti_claims]
    session[:lti_claims_expires_at] = cached_data[:lti_claims_expires_at]
    session[:lti_context_id] = cached_data[:lti_context_id]
    session[:lti_token] = token

    Rails.logger.info "LTI session restored from token (third-party cookie bypass)"
  end
  
  # Canvas iframe에서 표시 가능하도록 X-Frame-Options 제거
  # ngrok 등 프록시가 헤더를 추가할 수 있으므로 강제로 제거
  def allow_iframe
    # 모든 경우의 X-Frame-Options 헤더 제거 (대소문자 구분 없이)
    response.headers.delete('X-Frame-Options')
    response.headers.delete('x-frame-options')
    response.headers.delete('X-FRAME-OPTIONS')
    
    # Content-Security-Policy의 frame-ancestors도 설정 (선택사항)
    # response.headers['Content-Security-Policy'] = "frame-ancestors *"
  end
  
  # Admin 컨트롤러인지 확인 (보안을 위해 X-Frame-Options 유지)
  def admin_controller?
    self.class.name.start_with?('Admin::')
  end
end
