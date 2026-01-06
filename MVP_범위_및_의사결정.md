# MVP 범위 및 최종 의사결정

## 🎯 MVP 범위 정의

### ✅ MVP에 포함할 기능 (최소 기능)

1. **LTI 인증/인가** (이미 구현됨)
   - OIDC Login Flow
   - JWT 검증
   - LTI Claims 추출

2. **Project CRUD** (핵심 기능)
   - Project 목록 조회
   - Project 생성 (이름만)
   - Project 상세 조회
   - Project 삭제

3. **Canvas API 연동** (최소 기능)
   - Canvas API Token 생성
   - Assignment 생성 (기본만)
   - Assignment 조회

### ❌ MVP에서 제외할 기능 (나중에 추가)

1. **Project 수정** - 나중에 추가
2. **Assignment 수정/삭제** - 나중에 추가
3. **Submission 기능** - 나중에 추가
4. **Submission 통계** - 나중에 추가
5. **Slack 연동** - 나중에 추가
6. **에러 처리 고도화** - 기본만
7. **캐싱** - 나중에 추가
8. **테스트** - 나중에 추가

---

## 🔧 최종 의사결정

### 1. Client Secret 저장 방식 ✅

**결정**: 하이브리드 방식
- **프로덕션**: LtiPlatform DB에 저장 (암호화)
- **개발**: 환경변수 사용 가능 (fallback)

**구현**:
```ruby
# LtiPlatform에 client_secret 컬럼 추가
# 암호화 설정 (Rails 7.1+ encrypts)
# 환경변수 fallback 지원
```

### 2. 세션 관리 방식 ✅

**결정**: Rails 기본 세션 사용
- LTI Claims를 세션에 저장
- 세션 만료 시간: 1시간
- 세션 만료 시: LTI Launch 재요청 안내

**구현**:
```ruby
# LaunchController에서 세션에 저장
session[:lti_claims] = @lti_claims
session[:lti_claims_expires_at] = 1.hour.from_now

# ProjectsController에서 세션에서 로드
@lti_claims = session[:lti_claims]
```

### 3. Canvas User ID 매핑 ✅

**결정**: LTI Claims의 `canvas_user_id` 사용 (가장 간단)
- LTI Launch 시 받은 `canvas_user_id` 사용
- 없으면 에러 처리 (나중에 개선)

**구현**:
```ruby
canvas_user_id = @lti_claims[:canvas_user_id]
# 없으면 에러 또는 경고
```

### 4. 에러 처리 전략 ✅

**결정**: 기본 에러 처리만 (MVP)
- Canvas API 호출 실패 시 간단한 에러 메시지
- 나중에 고도화

**구현**:
```ruby
# 기본 try-catch
begin
  @canvas_api.create_assignment(...)
rescue => e
  flash[:error] = "과제 생성에 실패했습니다: #{e.message}"
  redirect_to projects_path
end
```

### 5. UI 스타일 ✅

**결정**: 기본 HTML + 간단한 CSS
- Bootstrap 또는 Tailwind 사용 (선택)
- 최소한의 스타일링만

---

## 📋 MVP 구현 체크리스트

### Phase 1: 데이터베이스 & 모델 (필수)
- [ ] Step 1: LtiContext 마이그레이션 생성
- [ ] Step 2: Project 마이그레이션 생성
- [ ] Step 3: Client Secret 마이그레이션 생성
- [ ] Step 4: 모델 생성 (LtiContext, Project)
- [ ] Step 5: LtiPlatform 모델에 client_secret 추가

### Phase 2: Canvas API 연동 (필수)
- [ ] Step 6: CanvasApiTokenGenerator 구현
- [ ] Step 7: CanvasApi::Client 구현
- [ ] Step 8: CanvasApi::AssignmentsClient 구현

### Phase 3: 비즈니스 로직 (필수)
- [ ] Step 9: ProjectService 구현 (최소 기능)
- [ ] Step 10: ProjectBuilder 구현 (생성만)

### Phase 4: 컨트롤러 & 라우팅 (필수)
- [ ] Step 11: ProjectsController 구현 (index, show, create, destroy)
- [ ] Step 12: LaunchController 수정 (세션 저장, 리다이렉트)
- [ ] Step 13: 라우팅 추가

### Phase 5: UI (필수)
- [ ] Step 14: ERB 뷰 템플릿 (index, show, new)
- [ ] Step 15: 기본 스타일링

### Phase 6: Admin UI (선택 - 나중에)
- [ ] Client Secret 입력 필드 추가

---

## 🚀 개발 시작 순서

### 1단계: 데이터베이스 & 모델 (Step 1-5)
### 2단계: Canvas API 연동 (Step 6-8)
### 3단계: 비즈니스 로직 (Step 9-10)
### 4단계: 컨트롤러 & 라우팅 (Step 11-13)
### 5단계: UI (Step 14-15)

---

## ✅ 최종 확인사항

### 개발 환경
- [x] LTI 프로젝트 워크스페이스에 추가됨
- [x] Canvas 프로젝트 워크스페이스에 추가됨
- [ ] Redis 설정 확인 (Nonce/State 저장용)
- [ ] PostgreSQL 설정 확인

### Canvas 설정
- [ ] Canvas Developer Key 생성
- [ ] Client ID 확인
- [ ] Client Secret 확인
- [ ] Canvas URL 확인

### 의사결정 완료
- [x] Client Secret 저장 방식 (하이브리드)
- [x] 세션 관리 방식 (Rails 기본 세션)
- [x] Canvas User ID 매핑 (canvas_user_id 사용)
- [x] 에러 처리 전략 (기본만)
- [x] UI 스타일 (기본 HTML)

---

## 🎯 MVP 목표

**최종 목표**: 
1. Canvas에서 LTI Tool 실행
2. Project 목록 보기
3. Project 생성 (이름 + Assignment 1개)
4. Project 상세 보기
5. Project 삭제

**동작 확인**:
- LTI Launch 성공
- Canvas API Token 생성 성공
- Canvas API로 Assignment 생성 성공
- Project DB에 저장 성공

---

**작성일**: 2025-01-06  
**작성자**: AI Assistant

