class ApplicationController < ActionController::Base
  # CSRF 토큰 검증 비활성화 (LTI Launch는 POST지만 외부에서 오므로)
  # Admin 컨트롤러는 CSRF 보호 필요하므로 skip 제거
  # LTI 컨트롤러만 skip 필요
  
  # Canvas iframe에서 표시 가능하도록 X-Frame-Options 제거 (전역)
  # LTI Tool은 Canvas iframe 내에서 실행되므로 필요
  # ngrok이 헤더를 추가할 수 있으므로 강제로 제거
  after_action :allow_iframe, unless: :admin_controller?
  
  private
  
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
