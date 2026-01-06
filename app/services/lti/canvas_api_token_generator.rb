# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas API 호출을 위한 Personal Access Token 사용
# - 사용자가 Canvas에서 직접 발급받아 입력
# - Client Credentials Grant 대신 Personal Access Token 사용 (더 확실함)
#
# 기술적 고려사항:
# - Personal Access Token은 LtiPlatform에 저장 (암호화)
# - 토큰 만료 시 수동 갱신 필요 (나중에 자동화 가능)
#
# 사용 시 고려사항:
# - Canvas에서 Personal Access Token 발급 필요
# - LtiPlatform에 canvas_api_token이 저장되어 있어야 함
# - 또는 환경변수로 관리 가능
module Lti
  class CanvasApiTokenGenerator
    class TokenGenerationError < StandardError; end
    
    # Canvas API용 Personal Access Token 조회
    # @param lti_platform [LtiPlatform] Canvas Platform 정보
    # @return [String] Access Token
    def self.generate(lti_platform)
      # Personal Access Token 조회
      get_canvas_api_token(lti_platform)
    end
    
    private
    
    # Canvas API Token 조회
    # 옵션 1: LtiPlatform에 저장 (암호화) - 우선순위
    # 옵션 2: 환경변수로 관리 - fallback
    def self.get_canvas_api_token(lti_platform)
      # 옵션 1: LtiPlatform에 저장된 Canvas API Token 사용 (우선순위)
      if lti_platform.canvas_api_token.present?
        lti_platform.canvas_api_token
      # 옵션 2: 환경변수로 관리 (fallback)
      elsif ENV["CANVAS_API_TOKEN_#{lti_platform.client_id}"].present?
        ENV["CANVAS_API_TOKEN_#{lti_platform.client_id}"]
      else
        raise TokenGenerationError, "Canvas API Token을 찾을 수 없습니다. LtiPlatform 또는 환경변수 CANVAS_API_TOKEN_#{lti_platform.client_id}를 확인하세요.\n\nCanvas에서 Personal Access Token을 발급받아 Admin 페이지에서 입력해주세요."
      end
    end
  end
end

