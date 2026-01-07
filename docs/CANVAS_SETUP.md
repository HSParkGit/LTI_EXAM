# Canvas LMS LTI 1.3 설정 가이드

## 개요
이 문서는 Canvas LMS에서 LTI 1.3 Tool Provider를 등록하기 위한 설정 가이드입니다.

**여러 Canvas 인스턴스 지원**: 이 Tool Provider는 여러 Canvas 인스턴스와 동시에 연동할 수 있습니다.

## Canvas Developer Key 설정

### 1. Canvas 관리자 페이지에서 Developer Key 생성
1. Canvas Admin → Developer Keys → + Developer Key → + LTI Key
2. 다음 정보를 입력:

#### 기본 설정
- **Key Name**: 예) "My LTI Tool"
- **Redirect URIs**: 
  ```
  https://your-tool.com/lti/launch
  ```
- **Initiation Login URL**: 
  ```
  https://your-tool.com/lti/login
  ```

#### OIDC Login 설정
- **Target Link URI**: 
  ```
  https://your-tool.com/lti/launch
  ```

#### JWK 설정
- 이 Tool Provider는 Canvas의 JWKS endpoint를 사용합니다.
- Canvas: `{canvas_instance_url}/api/lti/security/jwks`
- 별도 JWK 설정 불필요

### 2. Client ID 확인
Developer Key 생성 후, **Client ID**를 확인하세요.
- 형식: 숫자 (예: `10000000000001`)
- 이 값을 데이터베이스에 등록합니다 (아래 "Canvas Platform 등록" 참조)

## 데이터베이스 마이그레이션

먼저 데이터베이스 마이그레이션을 실행합니다:

```bash
mise exec -- rails db:migrate
```

## Canvas Platform 등록

데이터베이스에 Canvas 인스턴스를 등록합니다. **데이터베이스 방식이 권장됩니다** (환경변수는 fallback만 지원).

### 방법 1: Rails Console 사용 (권장)

```bash
mise exec -- rails console
```

```ruby
# Canvas 인스턴스 추가
LtiPlatform.create!(
  iss: "https://canvas.instructure.com",
  client_id: "10000000000001",
  name: "Canvas Production",
  active: true
)

# 여러 Canvas 인스턴스 추가 예시
LtiPlatform.create!(
  iss: "https://canvas.school1.edu",
  client_id: "20000000000002",
  name: "School 1 Canvas",
  active: true
)

# Platform 목록 확인
LtiPlatform.active.all
```

### 방법 2: SQL 직접 실행

```sql
INSERT INTO lti_platforms (iss, client_id, name, active, created_at, updated_at)
VALUES 
  ('https://canvas.instructure.com', '10000000000001', 'Canvas Production', true, NOW(), NOW()),
  ('https://canvas.school1.edu', '20000000000002', 'School 1 Canvas', true, NOW(), NOW());
```

### 방법 3: 환경변수 Fallback (하위 호환, 선택사항)

데이터베이스가 없을 때만 사용하는 fallback 방식:

```bash
# Redis URL (필수)
REDIS_URL=redis://localhost:6379/0

# 단일 Canvas (fallback)
# LTI_CLIENT_ID=10000000000001

# 또는 여러 Canvas (fallback)
# LTI_PLATFORMS='{"https://canvas.instructure.com": "10000000000001"}'
```

**주의**: 환경변수는 fallback이며, 데이터베이스에 등록된 Platform이 있으면 DB가 우선순위가 높습니다.

## Canvas Course에 Tool 추가

### 방법 1: Course Navigation에 추가
1. Course → Settings → Navigation
2. Developer Key로 등록한 Tool을 활성화
3. 학생/강사가 Course 메뉴에서 Tool에 접근

### 방법 2: Assignment에 External Tool로 추가
1. Course → Assignments → + Assignment
2. Submission Type: External Tool 선택
3. External Tool URL에서 등록한 Tool 선택
4. Tool이 새로운 탭에서 열림

## 테스트 시나리오

### 1. 기본 Launch 테스트
1. Canvas Course에서 Tool 실행
2. OIDC Login Flow 진행
3. Launch 화면에서 다음 정보 확인:
   - Course ID
   - User Role (Instructor / Student)
   - User Sub (Canvas 사용자 식별자)

### 2. Role 기반 기능 테스트
- **Instructor**: 강사 전용 기능 표시 확인
- **Student**: 학생 전용 기능 표시 확인

## 문제 해결

### JWT 검증 실패
- Canvas JWKS endpoint 접근 확인: `{canvas_url}/api/lti/security/jwks`
- Client ID가 올바른지 확인
- Redis가 실행 중인지 확인 (nonce 저장용)

### Redirect URI 불일치
- Canvas Developer Key의 Redirect URI와 실제 URL이 정확히 일치해야 함
- HTTPS 사용 권장 (프로덕션)
- 마지막 슬래시(/) 주의

### Nonce 오류
- Redis 연결 확인
- Nonce TTL (10분) 확인
- 동일 nonce 재사용 시도 방지

## 보안 고려사항

1. **HTTPS 필수**: 프로덕션 환경에서는 반드시 HTTPS 사용
2. **Client ID 보안**: 환경변수로 관리, 코드에 하드코딩 금지
3. **State 검증**: State도 nonce처럼 Redis에 저장하여 재사용 방지
4. **JWT 서명 검증**: 항상 Canvas JWKS endpoint에서 공개키 조회하여 검증

## 참고 자료

- [Canvas LTI 1.3 Documentation](https://canvas.instructure.com/doc/api/file.lti_dev_key_config.html)
- [IMS Global LTI 1.3 Specification](https://www.imsglobal.org/spec/lti/v1p3/)

