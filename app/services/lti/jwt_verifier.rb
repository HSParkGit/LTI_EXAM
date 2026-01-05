# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "base64"
require "openssl"

module Lti
  # JWT 검증을 위한 서비스 클래스
  # Canvas에서 전달된 id_token을 검증합니다.
  #
  # 검증 항목:
  # - JWT 서명 (Canvas JWKS endpoint에서 공개키 조회)
  # - iss (Issuer): Canvas 인스턴스 URL
  # - aud (Audience): Tool의 client_id
  # - exp (Expiration): 토큰 만료 시간
  # - nonce: 재사용 방지
  class JwtVerifier
    class VerificationError < StandardError; end

    # Canvas JWKS endpoint 캐시 (메모리)
    # 운영 환경에서는 Redis나 다른 캐시 시스템 사용 권장
    @jwks_cache = {}
    @jwks_cache_expiry = {}

    class << self
      # JWT 검증 및 payload 추출
      # @param id_token [String] Canvas에서 전달된 JWT
      # @param expected_iss [String] 예상되는 Canvas issuer (예: https://canvas.instructure.com)
      # @param expected_aud [String] Tool의 client_id (Canvas Developer Key에서 발급받은 값)
      # @param nonce [String] OIDC Login에서 생성한 nonce
      # @return [Hash] 검증된 JWT payload
      # @raise [VerificationError] 검증 실패 시
      def verify(id_token, expected_iss:, expected_aud:, nonce:)
        # JWT 디코딩 (서명 검증 없이 먼저 헤더 확인)
        header, payload = decode_without_verification(id_token)
        
        # JWKS endpoint에서 공개키 조회
        jwks = fetch_jwks(expected_iss)
        public_key = find_public_key(jwks, header["kid"])
        
        # JWT 서명 검증 및 디코딩
        decoded_token = decode_and_verify(id_token, public_key)
        
        # Claim 검증
        validate_claims(decoded_token, expected_iss: expected_iss, expected_aud: expected_aud, nonce: nonce)
        
        decoded_token
      end

      private

      # 서명 검증 없이 JWT 디코딩 (헤더 확인용)
      def decode_without_verification(token)
        header, payload, _signature = token.split(".")
        [JSON.parse(Base64.urlsafe_decode64(header)), JSON.parse(Base64.urlsafe_decode64(payload))]
      rescue StandardError => e
        raise VerificationError, "Invalid JWT format: #{e.message}"
      end

      # Canvas JWKS endpoint에서 공개키 조회
      def fetch_jwks(issuer)
        jwks_url = "#{issuer}/api/lti/security/jwks"
        
        # 캐시 확인 (5분 캐시)
        cache_key = jwks_url
        if @jwks_cache[cache_key] && @jwks_cache_expiry[cache_key] > Time.current
          return @jwks_cache[cache_key]
        end
        
        uri = URI(jwks_url)
        response = Net::HTTP.get_response(uri)
        
        unless response.is_a?(Net::HTTPSuccess)
          raise VerificationError, "Failed to fetch JWKS from Canvas: #{response.code}"
        end
        
        jwks = JSON.parse(response.body)
        
        # 캐시 저장
        @jwks_cache[cache_key] = jwks
        @jwks_cache_expiry[cache_key] = 5.minutes.from_now
        
        jwks
      rescue StandardError => e
        raise VerificationError, "Error fetching JWKS: #{e.message}"
      end

      # JWKS에서 kid로 공개키 찾기
      def find_public_key(jwks, kid)
        key_data = jwks["keys"].find { |key| key["kid"] == kid }
        raise VerificationError, "Public key not found for kid: #{kid}" unless key_data
        
        # JWK를 OpenSSL::PKey::RSA로 변환
        jwk_to_rsa(key_data)
      end

      # JWK를 RSA 공개키로 변환
      def jwk_to_rsa(jwk)
        n = Base64.urlsafe_decode64(jwk["n"])
        e = Base64.urlsafe_decode64(jwk["e"])
        
        # OpenSSL BigNum으로 변환
        n_bn = OpenSSL::BN.new(n, 2)
        e_bn = OpenSSL::BN.new(e, 2)
        
        # RSA 공개키 생성
        key = OpenSSL::PKey::RSA.new
        key.set_key(n_bn, e_bn, nil)
        
        key
      rescue StandardError => e
        raise VerificationError, "Error converting JWK to RSA: #{e.message}"
      end

      # JWT 서명 검증 및 디코딩
      def decode_and_verify(token, public_key)
        algorithm = "RS256"
        
        JWT.decode(token, public_key, true, { algorithm: algorithm }).first
      rescue JWT::DecodeError => e
        raise VerificationError, "JWT signature verification failed: #{e.message}"
      end

      # JWT claims 검증
      def validate_claims(payload, expected_iss:, expected_aud:, nonce:)
        # iss 검증
        if payload["iss"] != expected_iss
          raise VerificationError, "Invalid iss: expected #{expected_iss}, got #{payload['iss']}"
        end
        
        # aud 검증 (배열일 수 있음)
        aud = payload["aud"]
        aud_array = aud.is_a?(Array) ? aud : [aud]
        unless aud_array.include?(expected_aud)
          raise VerificationError, "Invalid aud: expected #{expected_aud}, got #{aud}"
        end
        
        # exp 검증 (만료 시간)
        exp = payload["exp"]
        if exp.nil? || Time.at(exp) < Time.current
          raise VerificationError, "Token has expired"
        end
        
        # nonce 검증
        # 1. JWT payload의 nonce와 전달받은 nonce가 일치하는지 확인
        payload_nonce = payload["nonce"]
        unless payload_nonce == nonce
          raise VerificationError, "Nonce mismatch: expected #{nonce}, got #{payload_nonce}"
        end
        
        # 2. NonceManager에서 nonce 소비 (재사용 방지)
        unless Lti::NonceManager.consume(nonce)
          raise VerificationError, "Nonce has already been used or expired"
        end
        
        true
      end
    end
  end
end

