# Canvas API 인증 방식 설계

## 📋 결정사항

**옵션 A: Canvas API용 OAuth 2.0 Access Token 사용** ✅

**중요**: LTI Advantage Access Token과 Canvas API Token은 **다릅니다**!

- **LTI Advantage Access Token**: AGS, NRPS 등 LTI 서비스 전용 (JWT Assertion 사용)
- **Canvas API Token**: 일반 Canvas API 호출용 (Client ID + Secret 사용)

**Canvas API 호출에는 일반 OAuth 2.0 Access Token이 필요합니다.**

LtiPlatform 모델에 **Client Secret**을 추가하고, Canvas URL과 함께 관리합니다.

---

## 🏗️ 데이터베이스 설계

### LtiPlatform 모델 확장

**마이그레이션 추가**:
```ruby
# db/migrate/xxx_add_client_secret_to_lti_platforms.rb
class AddClientSecretToLtiPlatforms < ActiveRecord::Migration[7.1]
  def change
    add_column :lti_platforms, :client_secret, :string, null: true
    # null: true로 시작 (기존 데이터 호환성)
    # 이후 not null로 변경 가능
  end
end
```

**LtiPlatform 모델 수정**:
```ruby
# app/models/lti_platform.rb
class LtiPlatform < ApplicationRecord
  # ... 기존 코드 ...
  
  # Client Secret 암호화 저장 (선택사항)
  # 또는 환경변수로 관리
  encrypts :client_secret if respond_to?(:encrypts)
  
  validates :client_secret, presence: true, if: -> { active? }
end
```

---

## 🔐 Canvas API Access Token 생성

### Canvas API용 OAuth 2.0 Access Token 획득 방법

**일반 Canvas API 호출**에는 **OAuth 2.0 Client Credentials Grant**를 사용합니다.

**Token Endpoint**: `{canvas_url}/login/oauth2/token`

**요청 방식**:
1. Client ID + Client Secret으로 요청
2. Token Endpoint로 POST 요청
3. Access Token 수신

**주의**: LTI Advantage Access Token (JWT Assertion)과는 다른 방식입니다!

### 구현 코드

```ruby
# app/services/lti/canvas_api_token_generator.rb
module Lti
  class CanvasApiTokenGenerator
    class TokenGenerationError < StandardError; end
    
    # Canvas API용 OAuth 2.0 Access Token 생성
    # @param lti_platform [LtiPlatform] Canvas Platform 정보
    # @return [String] Access Token
    def self.generate(lti_platform)
      # Client Secret 확인
      client_secret = get_client_secret(lti_platform)
      
      # Token Endpoint로 요청
      token_url = "#{lti_platform.actual_canvas_url}/login/oauth2/token"
      
      response = HTTParty.post(
        token_url,
        body: {
          grant_type: "client_credentials",
          client_id: lti_platform.client_id,
          client_secret: client_secret
        },
        headers: {
          "Content-Type" => "application/x-www-form-urlencoded"
        }
      )
      
      unless response.success?
        Rails.logger.error "Canvas API Token 생성 실패: #{response.code} - #{response.body}"
        raise TokenGenerationError, "Canvas API Token 생성 실패: #{response.code} - #{response.body}"
      end
      
      parsed_response = response.parsed_response
      
      unless parsed_response["access_token"]
        raise TokenGenerationError, "Canvas API Token 응답에 access_token이 없습니다: #{parsed_response}"
      end
      
      parsed_response["access_token"]
    rescue HTTParty::Error => e
      Rails.logger.error "Canvas API Token 요청 실패: #{e.message}"
      raise TokenGenerationError, "Canvas API Token 요청 실패: #{e.message}"
    end
    
    private
    
    # Client Secret 조회
    # 옵션 1: LtiPlatform에 저장 (암호화) - 추천
    # 옵션 2: 환경변수로 관리
    def self.get_client_secret(lti_platform)
      # 옵션 1: LtiPlatform에 저장된 Client Secret 사용 (우선순위)
      if lti_platform.client_secret.present?
        lti_platform.client_secret
      # 옵션 2: 환경변수로 관리 (fallback)
      elsif ENV["LTI_CLIENT_SECRET_#{lti_platform.client_id}"].present?
        ENV["LTI_CLIENT_SECRET_#{lti_platform.client_id}"]
      else
        raise TokenGenerationError, "Client Secret을 찾을 수 없습니다. LtiPlatform 또는 환경변수 LTI_CLIENT_SECRET_#{lti_platform.client_id}를 확인하세요."
      end
    end
  end
end
```

**중요**: 
- Canvas API 호출에는 **Client ID + Client Secret**만 필요합니다
- Private Key는 **LTI Advantage 서비스**용입니다 (AGS, NRPS)
- 일반 Canvas API (Assignments, Submissions)는 Client Credentials Grant만 사용

---

## 🔑 Client Secret 관리 전략

### 옵션 1: LtiPlatform 모델에 저장 (추천) ✅

**장점**:
- 각 Canvas 인스턴스별로 다른 Secret 관리 가능
- DB에 저장되어 관리 편리
- Admin UI에서 직접 입력 가능

**단점**:
- DB에 민감 정보 저장 (암호화 필요)

**구현**:
```ruby
# db/migrate/xxx_add_client_secret_to_lti_platforms.rb
class AddClientSecretToLtiPlatforms < ActiveRecord::Migration[7.1]
  def change
    add_column :lti_platforms, :client_secret, :string, null: true
    # null: true로 시작 (기존 데이터 호환성)
  end
end

# app/models/lti_platform.rb
class LtiPlatform < ApplicationRecord
  # Client Secret 암호화 저장
  encrypts :client_secret if respond_to?(:encrypts)
  
  validates :client_secret, presence: true, if: -> { active? }
end
```

### 옵션 2: 환경변수로 관리

**장점**:
- DB에 민감 정보 저장 안 함
- 간단한 구현

**단점**:
- 여러 Canvas 인스턴스 관리 시 복잡
- 환경변수 관리 필요

**구현**:
```ruby
# 환경변수 형식
# LTI_CLIENT_SECRET_10000000000001="secret_value_1"
# LTI_CLIENT_SECRET_10000000000002="secret_value_2"

# app/services/lti/canvas_api_token_generator.rb
def self.get_client_secret(lti_platform)
  env_key = "LTI_CLIENT_SECRET_#{lti_platform.client_id}"
  client_secret = ENV[env_key]
  
  raise TokenGenerationError, "환경변수 #{env_key}가 설정되지 않았습니다." unless client_secret
  
  client_secret
end
```

### 옵션 3: 하이브리드 (추천) ✅

**LtiPlatform에 저장하되, 환경변수 fallback 지원**

```ruby
def self.get_client_secret(lti_platform)
  # 1. LtiPlatform에 저장된 Client Secret (우선순위)
  if lti_platform.client_secret.present?
    lti_platform.client_secret
  # 2. 환경변수 fallback
  elsif ENV["LTI_CLIENT_SECRET_#{lti_platform.client_id}"].present?
    ENV["LTI_CLIENT_SECRET_#{lti_platform.client_id}"]
  else
    raise TokenGenerationError, "Client Secret을 찾을 수 없습니다."
  end
end
```

**추천**: 옵션 3 (하이브리드)
- 개발 환경: 환경변수 사용
- 프로덕션: LtiPlatform DB에 저장 (암호화)

---

## 🔄 Access Token 캐싱

**Access Token은 1시간 유효**하므로 캐싱 필요:

```ruby
# app/services/lti/canvas_api_token_generator.rb
def self.generate(lti_platform, scopes = default_scopes)
  cache_key = "canvas_api_token:#{lti_platform.iss}:#{lti_platform.client_id}"
  
  # 캐시에서 조회 (55분 캐시, 1시간 유효기간 고려)
  cached_token = Rails.cache.read(cache_key)
  return cached_token if cached_token.present?
  
  # 새 토큰 생성
  access_token = generate_new_token(lti_platform, scopes)
  
  # 캐시에 저장 (55분)
  Rails.cache.write(cache_key, access_token, expires_in: 55.minutes)
  
  access_token
end

private

def self.generate_new_token(lti_platform, scopes)
  # ... 기존 토큰 생성 로직 ...
end
```

---

## 📝 LtiPlatform 관리 UI 확장

**Admin UI에 Client Secret 입력 필드 추가**:

```ruby
# app/controllers/admin/lti_platforms_controller.rb
def lti_platform_params
  params.require(:lti_platform).permit(
    :iss,
    :client_id,
    :client_secret,        # 추가
    :canvas_url,
    :name,
    :active
  )
end
```

```erb
<!-- app/views/admin/lti_platforms/_form.html.erb -->
<div class="field">
  <%= form.label :client_secret, "Client Secret" %>
  <%= form.password_field :client_secret, class: "form-control", 
      value: @lti_platform.client_secret.present? ? "●●●●●●●●" : "" %>
  <small class="form-text text-muted">
    Canvas Developer Key의 Client Secret<br>
    (기존 값이 있으면 "●●●●●●●●"로 표시, 새로 입력하면 업데이트)
  </small>
</div>
```

**주의**: 
- `password_field` 사용 (화면에 표시되지 않음)
- 기존 값이 있으면 마스킹 처리
- 새로 입력하지 않으면 기존 값 유지

---

## 🔒 보안 고려사항

### 1. Client Secret 암호화 저장

```ruby
# Gemfile에 추가 (선택사항)
# gem 'attr_encrypted'  # Rails 7.1 미만인 경우

# app/models/lti_platform.rb
class LtiPlatform < ApplicationRecord
  # Rails 7.1+ encrypts 사용
  encrypts :client_secret if respond_to?(:encrypts)
end
```

### 2. 환경변수 사용 시

```ruby
# .env 파일 (절대 Git에 커밋하지 않음)
LTI_CLIENT_SECRET_10000000000001="secret_value_1"
LTI_CLIENT_SECRET_10000000000002="secret_value_2"

# .gitignore에 추가
.env
.env.local
.env.*.local
```

### 3. 로깅 시 민감 정보 제거

```ruby
# app/services/lti/canvas_api_token_generator.rb
def self.generate(lti_platform)
  Rails.logger.info "Canvas API Token 생성 시작", {
    platform_iss: lti_platform.iss,
    client_id: lti_platform.client_id,
    canvas_url: lti_platform.actual_canvas_url,
    # client_secret은 로깅하지 않음
    timestamp: Time.now
  }
  
  # ... 토큰 생성 로직 ...
end
```

### 4. Admin UI에서 Client Secret 마스킹

```ruby
# app/controllers/admin/lti_platforms_controller.rb
def edit
  @lti_platform = LtiPlatform.find(params[:id])
  # Client Secret은 화면에 표시하지 않음 (보안)
end

# app/views/admin/lti_platforms/_form.html.erb
# password_field 사용하여 입력값도 마스킹
```

---

## 📋 구현 체크리스트

### Step 1: 데이터베이스 확장
- [ ] `client_secret` 컬럼 추가 마이그레이션 생성
- [ ] 마이그레이션 실행

### Step 2: 모델 수정
- [ ] LtiPlatform 모델에 `client_secret` 검증 추가
- [ ] Client Secret 암호화 설정 (Rails 7.1+ encrypts)

### Step 3: CanvasApiTokenGenerator 구현
- [ ] Client Secret 조회 로직 (DB → 환경변수 fallback)
- [ ] OAuth 2.0 Client Credentials Grant 구현
- [ ] Token Endpoint 호출 로직
- [ ] Access Token 캐싱 (55분)
- [ ] 에러 처리

### Step 4: PlatformConfig 확장 (선택)
- [ ] `client_secret_for` 메서드 추가 (필요 시)

### Step 5: Admin UI 확장
- [ ] Client Secret 입력 필드 추가 (password_field)
- [ ] 기존 값 마스킹 처리
- [ ] 컨트롤러에서 permit 추가

---

## 🚀 사용 예시

```ruby
# ProjectsController에서 사용
def set_canvas_api_client
  lti_platform = LtiPlatform.find_by(iss: @lti_claims[:issuer])
  
  unless lti_platform
    raise "LTI Platform을 찾을 수 없습니다: #{@lti_claims[:issuer]}"
  end
  
  # Canvas API Access Token 생성
  access_token = Lti::CanvasApiTokenGenerator.generate(lti_platform)
  
  # Canvas API 클라이언트 생성
  @canvas_api = CanvasApi::Client.new(
    lti_platform.actual_canvas_url,
    access_token
  )
end
```

## 📝 Canvas Developer Key 설정

**Canvas에서 Developer Key 생성 시**:
1. **Client ID**: 자동 생성 (LtiPlatform.client_id에 저장)
2. **Client Secret**: 생성 후 복사 (LtiPlatform.client_secret에 저장)
3. **Canvas URL**: Canvas 인스턴스 URL (LtiPlatform.canvas_url에 저장)

**Admin UI에서 입력**:
- `iss`: Canvas가 보내는 발급자 (예: `https://canvas.instructure.com`)
- `client_id`: Developer Key의 Client ID
- `client_secret`: Developer Key의 Client Secret ⚠️ **민감 정보**
- `canvas_url`: 실제 Canvas 인스턴스 URL (Open Source인 경우)

---

**작성일**: 2025-01-06  
**작성자**: AI Assistant

