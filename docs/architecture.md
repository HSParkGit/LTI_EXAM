# 프로젝트 아키텍처

이 문서는 LTI 프로젝트의 전체 구조와 데이터 흐름을 설명합니다.

---

## 1. 전체 구조

```
┌─────────────────┐     LTI 1.3 Launch      ┌──────────────────┐
│     Canvas      │ ───────────────────────▶│   LTI Tool       │
│   (Platform)    │                         │   (Rails App)    │
└─────────────────┘                         └──────────────────┘
        │                                           │
        │  Canvas API                               │
        │  (REST)                                   │
        │◀──────────────────────────────────────────┘
        │
        ▼
┌─────────────────┐
│  Assignments    │
│  Submissions    │
│  Groups         │
│  Enrollments    │
└─────────────────┘
```

---

## 2. LTI Launch 흐름

```
1. Canvas에서 LTI Tool 클릭
   └─▶ POST /lti/login (OIDC Login Initiation)

2. LTI Tool에서 Canvas로 리다이렉트
   └─▶ Canvas Authorization Endpoint

3. Canvas에서 LTI Tool로 id_token 전달
   └─▶ POST /lti/launch (id_token + state)

4. JWT 검증 및 Claims 추출
   └─▶ 세션에 LTI Claims 저장

5. Projects 목록으로 리다이렉트
   └─▶ GET /projects
```

---

## 3. 데이터 모델

### 3.1 LtiPlatform
Canvas 인스턴스 정보 (Admin이 등록)

| 필드 | 설명 |
|-----|------|
| iss | Canvas URL (issuer) |
| client_id | Developer Key의 Client ID |
| client_secret | Developer Key의 Secret |
| actual_canvas_url | 실제 Canvas API URL |

### 3.2 LtiContext
LTI Launch된 컨텍스트 (코스) 정보

| 필드 | 설명 |
|-----|------|
| context_id | LTI Context ID |
| platform_iss | Platform ISS |
| canvas_course_id | Canvas 내부 Course ID |
| context_title | 코스 제목 |

### 3.3 Project
프로젝트 정보 (LTI Tool 자체 데이터)

| 필드 | 설명 |
|-----|------|
| name | 프로젝트 이름 |
| lti_context_id | 소속 LtiContext |
| assignment_ids | Canvas Assignment ID 배열 |

---

## 4. 세션에 저장되는 LTI Claims

`session[:lti_claims]` 구조:

```ruby
{
  # Context (코스) 정보
  course_id: "...",           # LTI Context ID
  context_title: "코스명",
  context_type: "Course",

  # 사용자 정보
  user_sub: "...",            # Canvas 사용자 고유 ID (sub)
  user_name: "홍길동",
  user_email: "user@example.com",

  # 역할 정보 (API 호출 없이 사용 가능!)
  user_role: :instructor,     # :instructor 또는 :student
  user_roles: [               # 전체 역할 배열 (LTI 1.3 표준)
    "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
  ],

  # Canvas 내부 ID (API 호출에 사용)
  canvas_user_id: 12345,
  canvas_course_id: 67890,

  # OIDC Claims
  issuer: "https://canvas.example.com",
  audience: "10000000000001",  # Client ID
}
```

---

## 5. API 호출 흐름

### 5.1 Projects 목록 (GET /projects)

```
1. load_lti_claims (세션에서)
2. set_lti_context (DB에서)
3. set_canvas_api_client (Token 생성)
4. ProjectService.projects_with_statistics
   └─▶ Canvas API: GET /courses/:id/assignments (각 프로젝트별)
   └─▶ Canvas API: GET /courses/:id/assignments/:id/submission_summary
5. determine_course_user_role
   └─▶ LTI Claims에서 확인 (API 호출 없음!)
```

### 5.2 Project 상세 (GET /projects/:id)

```
1. load_lti_claims
2. set_lti_context
3. set_canvas_api_client
4. ProjectService.project_with_assignments
   └─▶ Canvas API: GET /courses/:id/assignments/:id
   └─▶ Canvas API: GET /courses/:id/assignments/:id/submission_summary (교수)
   └─▶ Canvas API: GET /courses/:id/assignments/:id/submissions (교수, 그룹 멤버용)
   └─▶ Canvas API: GET /courses/:id/assignments/:id/submissions/:user_id (학생)
5. Canvas API: GET /group_categories/:id/groups (그룹 목록)
```

### 5.3 Project 생성 (POST /projects)

```
1. load_lti_claims
2. set_lti_context
3. set_canvas_api_client
4. ProjectBuilder.create_project
   └─▶ Canvas API: POST /courses/:id/assignments (각 Step별)
5. Project.save (로컬 DB)
```

---

## 6. Canvas API Token 생성

LTI 1.3에서는 Client Credentials Grant로 Access Token 획득:

```ruby
# Lti::CanvasApiTokenGenerator.generate(lti_platform)

POST {canvas_url}/login/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id={developer_key_id}
&client_secret={developer_key_secret}
&scope=url:GET|/api/v1/courses/:course_id/assignments ...
```

---

## 7. 주요 파일 위치

```
app/
├── controllers/
│   ├── projects_controller.rb      # 메인 컨트롤러
│   └── lti/
│       ├── login_controller.rb     # OIDC Login
│       └── launch_controller.rb    # LTI Launch
├── models/
│   ├── project.rb                  # 프로젝트 모델
│   ├── lti_context.rb              # LTI 컨텍스트
│   └── lti_platform.rb             # LTI 플랫폼 (Canvas)
├── services/
│   ├── project_service.rb          # 프로젝트 조회 로직
│   ├── project_builder.rb          # 프로젝트 생성/수정 로직
│   ├── canvas_api/
│   │   ├── client.rb               # 기본 HTTP 클라이언트
│   │   ├── assignments_client.rb   # Assignments API
│   │   ├── submissions_client.rb   # Submissions API
│   │   └── ...
│   └── lti/
│       ├── jwt_verifier.rb         # JWT 검증
│       └── canvas_api_token_generator.rb
└── views/projects/
    ├── index.html.erb              # 목록
    ├── show.html.erb               # 상세
    ├── new.html.erb                # 생성 폼
    └── edit.html.erb               # 수정 폼
```

---

*마지막 업데이트: 2026-01-21*
