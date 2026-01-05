class ApplicationController < ActionController::Base
  # CSRF 토큰 검증 비활성화 (LTI Launch는 POST지만 외부에서 오므로)
  # 프로덕션에서는 다른 방식의 검증 고려 필요
  skip_before_action :verify_authenticity_token
end
