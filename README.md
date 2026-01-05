# LTI 1.3 Tool Provider (Canvas LMS 연동)

Canvas LMS와 연동하는 LTI 1.3 Tool Provider의 최소 MVP 구현입니다.

## 기능

- ✅ LTI 1.3 OIDC Login Flow 구현
- ✅ LTI Launch 엔드포인트 (JWT 검증 포함)
- ✅ Canvas JWKS endpoint 연동
- ✅ Nonce 관리 (Redis 기반, replay attack 방지)
- ✅ Role 기반 화면 분기 (Instructor / Student)

## 기술 스택

- Ruby 3.3.6
- Rails 7.1.3
- JWT gem (JWT 검증)
- Redis (Nonce 저장)

## 빠른 시작

### 1. 의존성 설치

```bash
bundle install
```

### 2. Redis 실행

```bash
# Redis가 설치되어 있다면
redis-server

# 또는 Docker 사용
docker run -d -p 6379:6379 redis:alpine
```

### 3. 환경 변수 설정

`.env` 파일 생성 (또는 환경 변수 설정):

```bash
# Canvas Developer Key에서 발급받은 Client ID
LTI_CLIENT_ID=10000000000001

# Redis URL
REDIS_URL=redis://localhost:6379/0
```

### 4. 서버 실행

```bash
rails server
```

### 5. Canvas 설정

Canvas Developer Key를 생성하고 다음 정보를 설정하세요:

- **Redirect URI**: `https://your-tool.com/lti/launch`
- **Initiation Login URL**: `https://your-tool.com/lti/login`
- **Target Link URI**: `https://your-tool.com/lti/launch`

자세한 설정 방법은 [CANVAS_SETUP.md](./CANVAS_SETUP.md)를 참조하세요.

## 아키텍처

### 디렉토리 구조

```
app/
├── controllers/
│   └── lti/
│       ├── login_controller.rb    # OIDC Login Flow 처리
│       └── launch_controller.rb   # LTI Launch 처리
├── services/
│   └── lti/
│       ├── nonce_manager.rb       # Nonce 관리 (Redis)
│       └── jwt_verifier.rb        # JWT 검증, JWKS 조회
└── views/
    └── lti/
        └── launch/
            └── handle.html.erb    # Launch 성공 화면
```

### 주요 컴포넌트

#### 1. Lti::LoginController
- **역할**: OIDC Login Initiation 처리
- **엔드포인트**: `GET /lti/login`
- **기능**:
  - Canvas에서 전달된 `iss`, `login_hint`, `target_link_uri` 처리
  - `state`, `nonce` 생성
  - Canvas Authorization Endpoint로 리다이렉트

#### 2. Lti::LaunchController
- **역할**: LTI Launch 처리 및 화면 렌더링
- **엔드포인트**: `POST /lti/launch`
- **기능**:
  - `id_token` (JWT) 수신
  - JWT 검증 (서명, claims)
  - LTI Claims 추출 (course_id, user_role 등)
  - Role 기반 화면 분기

#### 3. Lti::JwtVerifier
- **역할**: JWT 검증 서비스
- **기능**:
  - Canvas JWKS endpoint에서 공개키 조회
  - JWT 서명 검증 (RS256)
  - Claims 검증 (iss, aud, exp, nonce)

#### 4. Lti::NonceManager
- **역할**: Nonce 관리 (Redis)
- **기능**:
  - Nonce 생성 및 Redis 저장 (TTL: 10분)
  - Nonce 소비 (일회성 사용 보장)

## LTI 1.3 Flow

```
1. Canvas → GET /lti/login
   - Query: iss, login_hint, target_link_uri
   
2. Tool → Canvas Authorization Endpoint
   - state, nonce 생성
   - Canvas로 리다이렉트
   
3. Canvas → POST /lti/launch
   - id_token (JWT) 전달
   - state 전달
   
4. Tool → JWT 검증
   - JWKS endpoint에서 공개키 조회
   - 서명 검증
   - Claims 검증 (iss, aud, exp, nonce)
   
5. Tool → Launch 화면 렌더링
   - Course ID, User Role 등 표시
```

## 개발 환경 설정

### Redis 설정 (개발 환경)

개발 환경에서 State 저장을 위해 Redis를 사용하려면:

1. Redis 실행 (위 참조)
2. `config/environments/development.rb`에서 cache_store 설정:

```ruby
config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
```

또는 `tmp/caching-dev.txt` 파일을 생성하여 메모리 캐시 사용:

```bash
touch tmp/caching-dev.txt
```

## 테스트

Canvas Course에서 Tool을 실행하여 다음을 확인:

1. OIDC Login Flow 정상 동작
2. Launch 화면에서 Course ID, User Role 표시
3. Instructor / Student 분기 정상 동작

## 보안 고려사항

1. **HTTPS 필수**: 프로덕션 환경에서는 반드시 HTTPS 사용
2. **Client ID 보안**: 환경변수로 관리, 코드에 하드코딩 금지
3. **Nonce 검증**: Redis를 통한 재사용 방지
4. **State 검증**: State도 일회성 사용 보장
5. **JWT 서명 검증**: Canvas JWKS endpoint에서 공개키 조회

## 참고 자료

- [Canvas LTI 1.3 Documentation](https://canvas.instructure.com/doc/api/file.lti_dev_key_config.html)
- [IMS Global LTI 1.3 Specification](https://www.imsglobal.org/spec/lti/v1p3/)
- [CANVAS_SETUP.md](./CANVAS_SETUP.md) - Canvas 설정 가이드
