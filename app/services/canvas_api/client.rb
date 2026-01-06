# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas API 호출을 위한 기본 클라이언트
# - Access Token을 사용한 인증
# - 공통 에러 처리 및 재시도 로직
#
# 기술적 고려사항:
# - Canvas API 표준 엔드포인트 사용
# - Rate Limiting 고려 (나중에 추가)
# - 에러 응답 처리
#
# 사용 시 고려사항:
# - Access Token은 CanvasApiTokenGenerator로 생성
# - Canvas URL은 LtiPlatform.actual_canvas_url 사용
module CanvasApi
  class Client
    class ApiError < StandardError; end
    
    def initialize(canvas_url, access_token)
      @canvas_url = canvas_url.chomp('/')
      @access_token = access_token
    end
    
    # GET 요청
    def get(path, params = {})
      request(:get, path, params: params)
    end
    
    # POST 요청
    def post(path, body = {})
      request(:post, path, body: body)
    end
    
    # PUT 요청
    def put(path, body = {})
      request(:put, path, body: body)
    end
    
    # DELETE 요청
    def delete(path)
      request(:delete, path)
    end
    
    private
    
    def request(method, path, params: nil, body: nil)
      uri = build_uri(path, params)
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      
      request_class = case method
                      when :get then Net::HTTP::Get
                      when :post then Net::HTTP::Post
                      when :put then Net::HTTP::Put
                      when :delete then Net::HTTP::Delete
                      end
      
      request = request_class.new(uri.path + (uri.query ? "?#{uri.query}" : ""))
      request['Authorization'] = "Bearer #{@access_token}"
      request['Content-Type'] = 'application/json'
      
      if body
        request.body = body.to_json
      end
      
      response = http.request(request)
      
      handle_response(response)
    end
    
    def build_uri(path, params)
      path = path.start_with?('/') ? path : "/#{path}"
      uri = URI.parse("#{@canvas_url}/api/v1#{path}")
      
      if params && params.any?
        uri.query = URI.encode_www_form(params)
      end
      
      uri
    end
    
    def handle_response(response)
      case response
      when Net::HTTPSuccess
        JSON.parse(response.body) if response.body.present?
      when Net::HTTPUnauthorized
        raise ApiError, "Canvas API 인증 실패: #{response.body}"
      when Net::HTTPForbidden
        raise ApiError, "Canvas API 권한 없음: #{response.body}"
      when Net::HTTPNotFound
        raise ApiError, "Canvas API 리소스를 찾을 수 없음: #{response.body}"
      when Net::HTTPTooManyRequests
        raise ApiError, "Canvas API Rate Limit 초과: #{response.body}"
      else
        raise ApiError, "Canvas API 오류: #{response.code} - #{response.body}"
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Canvas API 응답 파싱 실패: #{e.message}"
      raise ApiError, "Canvas API 응답 파싱 실패: #{e.message}"
    end
  end
end

