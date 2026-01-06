# frozen_string_literal: true

module Lti
  # LTI 컨트롤러들의 베이스 클래스
  # CSRF 토큰 검증 비활성화 (외부 Canvas에서 POST 요청)
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token
  end
end

