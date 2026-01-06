# frozen_string_literal: true

module Lti
  # LTI 컨트롤러들의 베이스 클래스
  # CSRF 토큰 검증 비활성화 (외부 Canvas에서 POST 요청)
  # X-Frame-Options 비활성화 (Canvas iframe에서 표시 가능하도록)
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token
    
    # Canvas는 iframe으로 LTI Tool을 로드하므로 X-Frame-Options를 비활성화해야 함
    after_action :allow_iframe
    
    private
    
    def allow_iframe
      response.headers.delete('X-Frame-Options')
      # 또는 명시적으로 설정: response.headers['X-Frame-Options'] = 'ALLOWALL'
    end
  end
end

