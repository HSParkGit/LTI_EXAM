# frozen_string_literal: true

# ngrok 등 프록시가 X-Frame-Options 헤더를 추가할 수 있으므로
# Rails 미들웨어 레벨에서 제거
#
# 참고: ngrok 무료 버전은 X-Frame-Options: SAMEORIGIN을 자동으로 추가합니다.
# 이 initializer는 응답 후 헤더를 제거하려고 시도하지만,
# ngrok이 프록시 레벨에서 추가하는 경우 완전히 제거되지 않을 수 있습니다.
#
# 해결 방법:
# 1. ngrok 유료 버전 사용 (response header override 가능)
# 2. ngrok 설정에서 헤더 제거
# 3. 다른 터널링 서비스 사용 (localtunnel, serveo 등)

Rails.application.config.after_initialize do
  # ActionDispatch::Response에 헤더 제거 로직 추가
  ActionDispatch::Response.class_eval do
    alias_method :original_set_header, :set_header unless method_defined?(:original_set_header)
    
    def set_header(name, value)
      # X-Frame-Options 헤더는 설정하지 않음
      return if name.to_s.downcase == 'x-frame-options'
      original_set_header(name, value)
    end
  end
end
