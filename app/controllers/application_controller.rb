class ApplicationController < ActionController::Base
  # CSRF 토큰 검증 비활성화 (LTI Launch는 POST지만 외부에서 오므로)
  # Admin 컨트롤러는 CSRF 보호 필요하므로 skip 제거
  # LTI 컨트롤러만 skip 필요
end
