# frozen_string_literal: true

module Lti
  # Nonce 관리를 위한 서비스 클래스
  # Redis를 사용하여 nonce 중복 사용 방지 (replay attack 방지)
  #
  # Nonce는 OIDC Login Flow에서 생성되어, Launch 시 검증됩니다.
  # Canvas에서 전달된 nonce가 이미 사용되었는지 확인합니다.
  class NonceManager
    NONCE_TTL = 10.minutes # Nonce 유효 기간 (LTI 1.3 권장: 10분)

    class << self
      # Nonce 생성 및 저장
      # @return [String] 생성된 nonce
      def generate
        nonce = SecureRandom.hex(32)
        redis_key = "lti:nonce:#{nonce}"
        
        # Redis에 nonce 저장 (TTL: 10분)
        redis.setex(redis_key, NONCE_TTL.to_i, "1")
        
        nonce
      end

      # Nonce 검증 및 소비
      # @param nonce [String] 검증할 nonce
      # @return [Boolean] nonce가 유효하고 사용 가능한 경우 true
      def consume(nonce)
        return false if nonce.blank?

        redis_key = "lti:nonce:#{nonce}"
        
        # Redis에서 nonce 삭제 (원자적 연산)
        # 삭제 성공 시 1, 실패 시 0 반환
        deleted = redis.del(redis_key)
        
        deleted == 1
      end

      private

      def redis
        @redis ||= Redis.new(url: redis_url)
      end

      def redis_url
        ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
      end
    end
  end
end

