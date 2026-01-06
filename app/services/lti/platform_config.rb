# frozen_string_literal: true

require "json"
require "uri"

module Lti
  # Canvas Platform 설정을 관리하는 서비스 클래스
  # 데이터베이스 기반으로 여러 Canvas 인스턴스의 iss(issuer)와 client_id를 매핑
  #
  # 사용 순서:
  #   1. 데이터베이스에서 조회 (LtiPlatform 모델)
  #   2. 환경변수 fallback (하위 호환: LTI_CLIENT_ID 또는 LTI_PLATFORMS)
  class PlatformConfig
    class ConfigurationError < StandardError; end

    # 캐시 (메모리 기반, 운영 환경에서는 Redis 권장)
    @cache = {}
    @cache_expiry = {}

    class << self
      # iss(issuer)에 해당하는 client_id 조회
      # @param iss [String] Canvas 인스턴스 URL
      # @return [String] Client ID
      # @raise [ConfigurationError] 설정이 없거나 iss가 등록되지 않은 경우
      def client_id_for(iss)
        # 캐시 확인
        cache_key = "platform:#{iss}"
        if cached = get_from_cache(cache_key)
          return cached
        end
        
        # 1. 데이터베이스에서 조회 (우선순위)
        platform = LtiPlatform.by_iss(iss).first
        if platform
          set_cache(cache_key, platform.client_id)
          return platform.client_id
        end
        
        # 2. 환경변수 fallback (하위 호환)
        if env_client_id = client_id_from_env(iss)
          set_cache(cache_key, env_client_id)
          return env_client_id
        end
        
        raise ConfigurationError, "No client_id configured for issuer: #{iss}. Please add it to the database or environment variables."
      end

      # 캐시 무효화 (Platform이 추가/수정/삭제될 때 호출)
      # @param iss [String, nil] 특정 iss만 무효화. nil이면 전체 무효화
      def clear_cache(iss = nil)
        if iss
          cache_key = "platform:#{iss}"
          @cache.delete(cache_key)
          @cache_expiry.delete(cache_key)
        else
          @cache.clear
          @cache_expiry.clear
        end
      end

      # 모든 등록된 Platform 목록 (DB + 환경변수)
      # @return [Array<String>] iss 목록
      def registered_issuers
        db_issuers = LtiPlatform.active.pluck(:iss)
        env_issuers = env_platforms.keys
        (db_issuers + env_issuers).uniq
      end

      private

      # 캐시에서 조회
      def get_from_cache(key)
        if @cache[key] && @cache_expiry[key] && @cache_expiry[key] > Time.current
          return @cache[key]
        end
        nil
      end

      # 캐시에 저장 (5분 TTL)
      def set_cache(key, value)
        @cache[key] = value
        @cache_expiry[key] = 5.minutes.from_now
      end

      # 환경변수에서 client_id 조회 (하위 호환)
      def client_id_from_env(iss)
        # LTI_PLATFORMS JSON 형식
        platforms = env_platforms
        return platforms[iss] if platforms[iss]
        
        # 정규화된 iss로도 찾기
        normalized_iss = normalize_iss(iss)
        platforms.each do |config_iss, client_id|
          if normalize_iss(config_iss) == normalized_iss
            return client_id
          end
        end
        
        # 단일 LTI_CLIENT_ID (모든 iss에 적용)
        ENV["LTI_CLIENT_ID"]
      end

      # 환경변수에서 Platform 설정 파싱
      def env_platforms
        platforms_json = ENV["LTI_PLATFORMS"]
        return {} unless platforms_json.present?
        
        begin
          config = JSON.parse(platforms_json)
          config.transform_keys(&:to_s)
        rescue JSON::ParserError
          {}
        end
      end

      # iss 정규화 (http vs https, 포트 등 정규화)
      def normalize_iss(iss)
        uri = URI.parse(iss)
        port_part = (uri.port == 80 || uri.port == 443 || uri.port.nil?) ? '' : ":#{uri.port}"
        "#{uri.host}#{port_part}#{uri.path}"
      rescue URI::InvalidURIError
        iss
      end
    end
  end
end
