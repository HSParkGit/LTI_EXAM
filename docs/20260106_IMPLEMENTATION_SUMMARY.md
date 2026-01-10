# LTI 1.3 Tool Provider 구현 요약

이 문서는 Canvas LMS와 연동하는 LTI 1.3 Tool Provider의 구현 과정과 주요 작업 내용을 정리한 것입니다.

## 📋 프로젝트 개요

**목표**: Canvas LMS에서 외부 도구(LTI 1.3)로 실행 가능한 최소 MVP 구현
**기술 스택**: Ruby on Rails 7, JWT, Redis
**Canvas 버전**: Canvas Open Source (self-hosted) 지원

---

## ✅ 구현 완료된 기능

### 1. LTI 1.3 OIDC Login Flow
- **엔드포인트**: `GET/POST /lti/login`
- **기능**:
  - Canvas에서 전달된 `iss`, `login_hint`, `target_link_uri`, `lti_message_hint` 처리
  - `state`, `nonce` 생성 및 Redis에 저장
  - Canvas Authorization Endpoint로 리다이렉트
  - `scope=openid` 파라미터 포함 (Canvas 요구사항)

### 2. LTI Launch 처리
- **엔드포인트**: `POST /lti/launch`
- **기능**:
  - `id_token` (JWT) 수신 및 검증
  - Canvas JWKS endpoint에서 공개키 조회
  - JWT 서명 검증 (RS256)
  - Claims 검증 (iss, aud, exp, nonce)
  - State 검증 (일회성 사용 보장)
  - Nonce 검증 (재사용 방지)

### 3. Canvas Open Source 지원
- **문제**: Canvas Open Source는 `iss`로 `https://canvas.instructure.com`을 보내지만, 실제 endpoint는 다른 도메인 사용
- **해결**:
  - `LtiPlatform` 모델에 `canvas_url` 컬럼 추가
  - `iss`와 실제 Canvas 인스턴스 URL 분리 저장
  - Authorization endpoint, JWKS endpoint 생성 시 `canvas_url` 사용

### 4. 사용자 정보 추출
- **추출 가능한 정보**:
  - 사용자: 이름, 이메일, 프로필 사진, User Sub, Canvas User ID
  - 코스: 코스 ID, 제목, 타입, Canvas Course ID
  - 역할: 강사/학생 구분, 전체 역할 배열
  - Resource Link: 과제/모듈 정보 (선택적)
  - LTI 메타데이터: Deployment ID, Message Type, Version 등

### 5. 역할 기반 화면 분기
- Instructor/Student 자동 감지
- 역할별 기능 분기 렌더링

### 6. 여러 Canvas 인스턴스 지원
- 데이터베이스 기반 Platform 관리 (`LtiPlatform` 모델)
- Admin UI로 Platform 등록/수정/삭제
- 환경변수 fallback 지원 (하위 호환)

### 7. 보안 기능
- X-Frame-Options 헤더 제거 (Canvas iframe 표시 가능)
- OpenSSL 3.0 호환 JWK→RSA 변환 (ASN1::Sequence 사용)
- Nonce 재사용 방지 (Redis 기반)
- State 일회성 사용 보장

---

## 🏗️ 아키텍처

### 디렉토리 구조
```
app/
├── controllers/
│   ├── lti/
│   │   ├── base_controller.rb          # LTI 베이스 컨트롤러 (CSRF skip, X-Frame-Options 제거)
│   │   ├── login_controller.rb          # OIDC Login Flow 처리
│   │   └── launch_controller.rb         # LTI Launch 처리
│   └── admin/
│       └── lti_platforms_controller.rb  # Platform 관리 UI
├── models/
│   └── lti_platform.rb                  # Canvas Platform 모델 (iss, client_id, canvas_url)
├── services/
│   └── lti/
│       ├── nonce_manager.rb             # Nonce 관리 (Redis)
│       ├── jwt_verifier.rb              # JWT 검증, JWKS 조회
│       └── platform_config.rb          # Platform 설정 조회 (DB + 캐시)
└── views/
    └── lti/
        └── launch/
            └── handle.html.erb          # Launch 성공 화면
```

### 주요 컴포넌트

#### 1. Lti::LoginController
- **역할**: OIDC Login Initiation
- **주요 메서드**:
  - `initiate`: Canvas 요청 처리, state/nonce 생성, Canvas로 리다이렉트
  - `build_authorization_url`: Canvas Authorization Endpoint URL 생성

#### 2. Lti::LaunchController
- **역할**: LTI Launch 처리 및 화면 렌더링
- **주요 메서드**:
  - `handle`: Launch 요청 처리, JWT 검증, Claims 추출
  - `extract_lti_claims`: JWT payload에서 모든 LTI 정보 추출
  - `determine_user_role`: 역할 판단 (Instructor/Student)

#### 3. Lti::JwtVerifier
- **역할**: JWT 검증 서비스
- **주요 메서드**:
  - `verify`: JWT 검증 및 payload 반환
  - `fetch_jwks`: Canvas JWKS endpoint에서 공개키 조회
  - `jwk_to_rsa`: JWK를 RSA 공개키로 변환 (OpenSSL 3.0 호환)

#### 4. Lti::NonceManager
- **역할**: Nonce 관리 (재사용 방지)
- **기능**: Redis에 저장 (TTL: 10분), 일회성 사용 보장

#### 5. Lti::PlatformConfig
- **역할**: Platform 설정 조회
- **기능**: DB 조회 (우선순위) → 환경변수 fallback, 캐싱 (5분 TTL)

#### 6. LtiPlatform (Model)
- **역할**: Canvas Platform 정보 저장
- **필드**: `iss`, `client_id`, `canvas_url`, `name`, `active`

---

## 🔧 주요 구현 세부사항

### 1. Canvas Open Source 지원

**문제**: Canvas Open Source는 `iss`로 `https://canvas.instructure.com`을 보내지만, 실제 endpoint는 다른 도메인 사용

**해결**:
```ruby
# LtiPlatform 모델에 canvas_url 추가
add_column :lti_platforms, :canvas_url, :string

# PlatformConfig에서 canvas_url 조회
def canvas_url_for(iss)
  platform = LtiPlatform.by_iss(iss).first
  platform.actual_canvas_url  # canvas_url || iss
end

# Authorization endpoint 생성 시 canvas_url 사용
auth_endpoint = "#{canvas_url}/api/lti/authorize_redirect"
```

### 2. OIDC Login Flow 파라미터

**필수 파라미터**:
- `scope: "openid"` (Canvas 요구사항)
- `response_type: "id_token"`
- `response_mode: "form_post"`
- `lti_message_hint` (Canvas가 보낸 경우 전달)

**코드**:
```ruby
params = {
  response_type: "id_token",
  client_id: client_id,
  redirect_uri: target_link_uri,
  login_hint: login_hint,
  state: state,
  response_mode: "form_post",
  nonce: nonce,
  prompt: "none",
  scope: "openid"
}
params[:lti_message_hint] = lti_message_hint if lti_message_hint.present?
```

### 3. OpenSSL 3.0 호환 JWK 변환

**문제**: OpenSSL 3.0에서 `set_key` 메서드 제거

**해결**:
```ruby
def jwk_to_rsa(jwk)
  n = Base64.urlsafe_decode64(jwk["n"])
  e = Base64.urlsafe_decode64(jwk["e"])
  
  n_bn = OpenSSL::BN.new(n, 2)
  e_bn = OpenSSL::BN.new(e, 2)
  
  # OpenSSL 3.0 호환 방식
  seq = OpenSSL::ASN1::Sequence([
    OpenSSL::ASN1::Integer(n_bn),
    OpenSSL::ASN1::Integer(e_bn)
  ])
  
  OpenSSL::PKey::RSA.new(seq.to_der)
end
```

### 4. X-Frame-Options 제거

**문제**: Canvas는 iframe으로 LTI Tool을 로드하는데, X-Frame-Options가 있으면 표시 불가

**해결**:
```ruby
# Lti::BaseController
after_action :allow_iframe

def allow_iframe
  response.headers.delete('X-Frame-Options')
end
```

### 5. State 및 Nonce 관리

**State**:
- Redis에 저장 (TTL: 10분)
- Launch 시 일회성 사용 후 삭제

**Nonce**:
- Redis에 저장 (TTL: 10분)
- JWT 검증 후 일회성 사용 보장

### 6. LTI Claims 추출

**추출하는 정보**:
- Context (코스): id, title, type, label
- Resource Link (과제/모듈): id, title, description
- 사용자: sub, name, email, picture, given_name, family_name
- 역할: roles 배열
- LTI 메타데이터: deployment_id, message_type, version, target_link_uri
- Canvas 특정: canvas_user_id, canvas_course_id, canvas_account_id

---

## 📦 의존성

### Gemfile
```ruby
gem "rails", "~> 7.1.3"
gem "jwt"                    # JWT 검증
gem "redis", ">= 4.0.1"      # Nonce/State 저장
gem "pg", "~> 1.1"           # PostgreSQL
```

### 환경 설정
- Redis: Nonce/State 저장용
- PostgreSQL: Platform 정보 저장용
- `tmp/caching-dev.txt`: 개발 환경 캐시 활성화

---

## 🔐 보안 고려사항

1. **JWT 검증**: 항상 Canvas JWKS endpoint에서 공개키 조회
2. **Nonce 재사용 방지**: Redis를 통한 일회성 사용 보장
3. **State 검증**: 일회성 사용 보장
4. **Claims 검증**: iss, aud, exp, nonce 모두 검증
5. **X-Frame-Options**: Canvas iframe 표시를 위해 제거 (필요한 경우)

---

## 🐛 해결한 주요 이슈

### 1. "lti_message_hint is missing" 에러
- **원인**: Canvas가 보낸 `lti_message_hint`를 전달하지 않음
- **해결**: Authorization URL 생성 시 `lti_message_hint` 파라미터 추가

### 2. "The 'scope' must be 'openid'" 에러
- **원인**: OAuth 2.0 Authorization Request에 `scope=openid` 누락
- **해결**: `scope: "openid"` 파라미터 추가

### 3. "Invalid or expired state" 에러
- **원인**: 개발 환경에서 캐시가 비활성화되어 state가 저장되지 않음
- **해결**: `tmp/caching-dev.txt` 파일 생성하여 메모리 캐시 활성화

### 4. "Error converting JWK to RSA: rsa#set_key= is incompatible with OpenSSL 3.0"
- **원인**: OpenSSL 3.0에서 `set_key` 메서드 제거
- **해결**: ASN1::Sequence를 사용한 OpenSSL 3.0 호환 방식으로 변경

### 5. "Refused to display in a frame because it set 'X-Frame-Options' to 'sameorigin'"
- **원인**: Rails 기본 X-Frame-Options 헤더로 인해 Canvas iframe에서 표시 불가
- **해결**: Lti::BaseController에서 X-Frame-Options 헤더 제거

### 6. 사용자 정보가 N/A로 표시됨
- **원인**: Canvas Developer Key의 Privacy Level이 Anonymous로 설정됨
- **해결**: Privacy Level을 Public으로 변경 (Canvas 설정)

---

## 📝 Canvas Developer Key 설정

### 필수 설정
- **Privacy Level**: `Public` (이름, 이메일 전달)
- **Redirect URIs**: `https://your-tool.com/lti/launch`
- **Initiation Login URL**: `https://your-tool.com/lti/login`
- **Target Link URI**: `https://your-tool.com/lti/launch`

### Services 설정
- **현재는 체크 불필요** (LTI 1.3 Core만 구현)
- 향후 점수 업로드 필요 시 AGS 체크
- 향후 학생 목록 필요 시 NRPS 체크

---

## 🚀 다음 단계 (미구현)

### Canvas API 연동
- 학생 목록 조회
- 과제 목록/상세 조회
- 제출물 조회
- 성적 업로드/조회

### LTI Advantage 확장
- AGS (Assignment and Grade Services): 점수 업로드
- NRPS (Names and Role Provisioning Services): 사용자 목록
- Deep Linking: 콘텐츠 선택 및 추가

---

## 📚 참고 자료

- [LTI 1.3 Core Specification](https://www.imsglobal.org/spec/lti/v1p3/)
- [Canvas LTI Documentation](https://canvas.instructure.com/doc/api/file.lti_dev_key_config.html)
- [Canvas API Documentation](https://canvas.instructure.com/doc/api/)

---

## 💡 주요 학습 포인트

1. **LTI 1.3은 OAuth 2.0 + OpenID Connect 기반**
2. **Canvas Open Source는 iss와 실제 URL이 다를 수 있음**
3. **OpenSSL 3.0 호환성을 고려한 JWK 변환 필요**
4. **Canvas iframe 표시를 위해 X-Frame-Options 제거 필요**
5. **Privacy Level 설정에 따라 사용자 정보 전달 여부 결정**
6. **State와 Nonce 모두 일회성 사용 보장 필요**

---

## 🎯 핵심 코드 패턴

### JWT 검증 플로우
```
1. JWT 디코딩 (서명 검증 없이 헤더 확인)
2. JWKS endpoint에서 공개키 조회 (캐싱)
3. JWT 서명 검증
4. Claims 검증 (iss, aud, exp, nonce)
5. Nonce 소비 (재사용 방지)
```

### Platform 설정 조회 플로우
```
1. 캐시 확인 (5분 TTL)
2. 데이터베이스 조회 (우선순위)
3. 환경변수 fallback (하위 호환)
4. 에러 발생 (설정 없음)
```

### LTI Launch 플로우
```
1. Canvas → GET /lti/login (iss, login_hint, target_link_uri)
2. Tool → state, nonce 생성 및 저장
3. Tool → Canvas Authorization Endpoint로 리다이렉트
4. Canvas → POST /lti/launch (id_token, state)
5. Tool → JWT 검증 및 Claims 추출
6. Tool → 화면 렌더링
```

---

이 문서는 다른 프로젝트에서 LTI 1.3 구현을 참고하거나 '프로젝트' 기능을 가져올 때 사용할 수 있습니다.

