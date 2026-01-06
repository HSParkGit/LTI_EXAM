# frozen_string_literal: true

# 세션 쿠키 설정
# Canvas iframe에서 쿠키가 전달되도록 SameSite=None, Secure 설정 필요
# ngrok을 통한 HTTPS 접근 시 Secure 쿠키 필요
Rails.application.config.session_store :cookie_store,
  key: '_lti_tool_session',
  # ngrok을 통한 HTTPS 접근을 위해 Secure를 true로 설정
  # SameSite=None을 사용하려면 Secure가 true여야 함
  secure: Rails.env.production? || ENV['FORCE_SSL'].present? || true, # ngrok HTTPS용
  # SameSite=None은 cross-site 요청(iframe)에서 쿠키 전달을 위해 필요
  same_site: :none,
  httponly: true

