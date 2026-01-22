# Canvas Project to LTI 변환 프로젝트 비교 분석

## 개요

이 문서는 Canvas에 내장된 프로젝트 기능(React 기반)을 LTI 방식(ERB 기반)으로 분리한 프로젝트의 현재 상태를 분석하고, 누락된 기능과 개선이 필요한 부분을 정리한 것입니다.

---

## 1. 프로젝트 목록 (Index)

### Canvas 원본 (React)
**파일 위치**: `ui/features/hy_projects/`
- `index.jsx` - 엔트리 포인트
- `react/ProjectsPage.tsx` - 메인 페이지 컴포넌트
- `react/ProjectsDesktop.tsx` - 데스크톱 뷰
- `react/ProjectsMobile.tsx` - 모바일 뷰
- `react/ProjectTable.tsx` - 테이블 컴포넌트
- `react/utils.ts` - 유틸리티 함수

**구현된 기능**:
- 프로젝트 4개 섹션 분류:
  - Upcoming (모든 Step의 시작일이 미래)
  - Current (1개 이상의 Step이 진행 중)
  - Past (모든 Step의 마감일이 지남)
  - Unpublished (비공개 프로젝트, 교수만 표시)
- Step 상태 배지 (Past/Current/Upcoming)
- 교수 뷰: 채점 통계 (Needs Grading, Graded 카운트)
- 학생 뷰: 제출 상태 (제출 완료/미제출)
- 데스크톱/모바일 반응형 UI
- 프로젝트 카드 드롭다운 메뉴 (수정/삭제)

### LTI 버전 (ERB)
**파일 위치**: `app/views/projects/`
- `index.html.erb` - 메인 뷰
- `_project_row.html.erb` - 프로젝트 행 partial

**구현 상태**:
| 기능 | 상태 | 비고 |
|------|------|------|
| 프로젝트 테이블 표시 | O | 테이블 형식 |
| Step 상태 배지 | O | Past/Current/Upcoming |
| 교수/학생 역할 분기 | O | `@user_role` 사용 |
| 채점 통계 (교수) | O | Needs Grading, Graded |
| 제출 상태 (학생) | O | 제출 완료/미제출 |
| 드롭다운 메뉴 (수정/삭제) | O | JavaScript 구현 |
| **섹션 분류** | **O** | **Upcoming/Current/Past/Unpublished 4개 섹션** |
| 반응형 UI | 부분적 | 모바일 전용 뷰 없음 |

### 구현 완료된 로직
1. **프로젝트 섹션 분류** (2026-01-21 완료)
   - `ProjectService#classify_projects` 메서드로 4개 섹션 분류
   - `index.html.erb`에서 섹션별 접이식 UI 구현
   - 학생은 Unpublished 프로젝트 미표시

---

## 2. 프로젝트 생성/수정 (New/Edit)

### Canvas 원본 (React)
**파일 위치**: `ui/features/hy_project_new_v2/react/`
- `CreateProjectForm.jsx` - 메인 폼 컴포넌트 (923줄)
- `AssignmentForm.jsx` - Step별 과제 폼
- `SubmissionTypeSelector.jsx` - 제출 타입 선택
- `AllowedAttemptsSelector.jsx` - 제출 횟수 선택
- `PeerReviewOptionField.jsx` - 피어 리뷰 옵션
- `ValidationErrorModal.jsx` - 유효성 검사 에러 모달
- `ProjectCreateConfirmModal.jsx` - 생성 확인 모달

**구현된 기능**:
- Project Title 입력
- Group Category Selector (Backbone.js 뷰)
- Assignment Group Selector (Backbone.js 뷰)
- Step Generator (드롭다운으로 여러 Step 관리)
  - Step 추가/삭제
  - Step별 날짜 표시
- Step별 과제 설정:
  - 제목, 설명 (RCE 에디터)
  - 배점, 채점 타입
  - 시작일/마감일/종료일
  - 제출 타입, 파일 확장자 제한
  - 제출 횟수 제한
  - 피어 리뷰 옵션
- Slack 채널 생성 옵션
- 유효성 검사:
  - 프로젝트 제목 필수
  - 그룹 카테고리 필수
  - Step 제목 필수
  - 마감일 필수
  - 날짜 순서 검증 (시작일 < 마감일 < 종료일)
  - Slack 채널명 길이 검증 (80자)
- Save / Save & Publish 분리

### LTI 버전 (ERB)
**파일 위치**: `app/views/projects/`
- `new.html.erb` - 생성 뷰
- `edit.html.erb` - 수정 뷰

**현재 상태**: 대부분 구현 완료 (2026-01-21 업데이트)

**구현 상태**:
| 기능 | 상태 | 비고 |
|------|------|------|
| Project Title 입력 | O | 기본 input |
| Group Category Selector | **O** | **Canvas API로 조회 → select 태그** |
| Assignment Group Selector | **O** | **Canvas API로 조회 → select 태그** |
| Step Generator | **O** | **JavaScript로 동적 추가/삭제 구현** |
| Step별 과제 설정 | **O** | **아래 세부사항 참조** |
| Slack 채널 생성 옵션 | X | Canvas에서만 지원 |
| 유효성 검사 | 부분적 | 기본 required만, 서버 검사 필요 |
| Save & Publish 분리 | **O** | **두 개 버튼 구현됨** |

**Step별 과제 설정 세부 구현 상태**:
| 설정 항목 | 상태 | 비고 |
|-----------|------|------|
| Assignment Name | O | input, required |
| Description | O | textarea |
| Points | O | number input |
| Display Grade as | O | select (배점/완료/백분율/등급) |
| Submission Type | O | Online/No Submission |
| Online Entry Options | O | Website URL, File Uploads |
| Restrict File Types | O | 체크박스 UI만 (확장자 입력 미구현) |
| Submission Attempts | O | Unlimited/Limited |
| Peer Reviews | O | 체크박스 |
| Due Date / Available from / Until | O | datetime-local |

### 남은 개선 사항
1. **파일 확장자 제한 입력 UI**
   - 현재 체크박스만 있고, 실제 확장자 입력 필드 미구현

2. **서버 사이드 유효성 검사 강화**
   - 날짜 순서 검증 (시작일 < 마감일 < 종료일)
   - 프로젝트 제목 중복 검사

3. **Slack 채널 생성**
   - LTI에서는 지원 불가 (Canvas 내부 기능)

---

## 3. 프로젝트 상세 (Show)

### Canvas 원본 (React)
**파일 위치**: `ui/features/hy_project_show/react/`
- `AssignmentGroupContent.jsx` - 교수용 과제 상세
- `AssignmentGroupHeader.jsx` - 과제 헤더
- `AssignmentSubmissions.jsx` - 교수용 채점 섹션
- `StudentAssignmentGroupContent.jsx` - 학생용 과제 상세
- `StudentAssignmentSubmissions.jsx` - 학생용 제출 섹션
- `AddTaskDialog.tsx` - Task 추가 모달
- `UpdateTaskDialog.tsx` - Task 수정 모달
- `PdfUploaderDialog.tsx` - PDF 업로드 모달
- `PeerReviewDialog.tsx` - 피어 리뷰 모달

**교수 뷰 기능**:
- Group Selector (그룹별 조회)
- 과제 상세 정보 (설명, 배점, 제출 타입 등)
- **To Do 섹션** (Task 관리)
  - Task 카드 가로 스크롤
  - Task 추가/수정/완료
  - 담당자 지정, 마감일 설정
- Evaluations 섹션
  - 그룹 멤버별 제출 상태
  - SpeedGrader 링크
  - Assign Peer Review 버튼

**학생 뷰 기능**:
- Submission Phase (3단계)
  1. Submit - 과제 제출
  2. Review - 피어 리뷰 (조건부)
  3. Feedback - 결과 확인
- 자체 제출 다이얼로그 (URL, PDF)
- 피어 리뷰 선택 모달 (여러 피어 리뷰 대상 선택)
- 제출 이력 및 재제출
- Allowed Attempts 표시

### LTI 버전 (ERB)
**파일 위치**: `app/views/projects/show.html.erb`

**구현 상태**:

#### 교수 뷰
| 기능 | 상태 | 비고 |
|------|------|------|
| Group Selector | O | select 태그 |
| 과제 상세 정보 | O | 설명, 배점, 제출 타입 |
| **To Do 섹션** | **X** | **Task 관리 기능 없음** |
| Evaluations 섹션 | O | 그룹 멤버별 표시 |
| SpeedGrader 링크 | O | 외부 링크 |
| Assign Peer Review | O | 외부 링크 |

#### 학생 뷰
| 기능 | 상태 | 비고 |
|------|------|------|
| Submission Phase UI | O | Submit/Review/Feedback |
| Submit 버튼 | O | **Canvas 페이지로 리다이렉트** |
| 재제출 (Resubmit) | O | attempts 표시 |
| Peer Review | O | **Canvas 페이지로 리다이렉트** |
| View Submission | O | **Canvas 페이지로 리다이렉트** |
| **자체 제출 다이얼로그** | **X** | **Canvas 페이지 의존** |
| **피어 리뷰 선택 모달** | **X** | **Canvas 페이지 의존** |

### 누락된 로직
1. **To Do 섹션 (교수용)**
   - Task 모델 및 API 필요
   - Task CRUD 기능
   - Task 완료 처리

2. **자체 제출 다이얼로그 (학생용)**
   - 현재는 Canvas 페이지로 리다이렉트
   - LTI 내에서 제출하려면 Canvas API를 통한 파일 업로드 구현 필요
   - 복잡도가 높아 현재 구현은 Canvas 리다이렉트로 적절함

3. **피어 리뷰 선택 모달 (학생용)**
   - 여러 피어 리뷰 대상 중 선택
   - Canvas API로 assessment_requests 조회 필요

---

## 4. 사용 중인 Canvas API

### LTI 프로젝트의 Canvas API 클라이언트

| 클라이언트 | 파일 | 주요 기능 |
|-----------|------|----------|
| `CanvasApi::Client` | `client.rb` | 기본 HTTP 클라이언트, 인증, 에러 처리 |
| `CanvasApi::AssignmentsClient` | `assignments_client.rb` | Assignment CRUD, 조회 |
| `CanvasApi::SubmissionsClient` | `submissions_client.rb` | 제출물 조회, 통계 |
| `CanvasApi::CoursesClient` | `courses_client.rb` | 코스 정보 조회 |
| `CanvasApi::EnrollmentsClient` | `enrollments_client.rb` | 수강생 목록 조회 |
| `CanvasApi::GroupCategoriesClient` | `group_categories_client.rb` | 그룹 카테고리, 그룹 목록 |
| `CanvasApi::AssignmentGroupsClient` | `assignment_groups_client.rb` | 과제 그룹 목록 |

### API 사용 목적

| 기능 | 원본 (Canvas 내부) | LTI (외부 API 호출) |
|------|-------------------|-------------------|
| 프로젝트 목록 조회 | DB 직접 쿼리 | `AssignmentsClient.list` |
| 제출 통계 조회 | `Submission` 모델 쿼리 | `SubmissionsClient.statistics` |
| 그룹 목록 조회 | `GroupCategory.groups` | `GroupCategoriesClient.list_groups` |
| 수강생 목록 조회 | `Course.students` | `EnrollmentsClient.list` |
| 과제 생성/수정 | `Assignment` 모델 | `AssignmentsClient.create/update` |

---

## 5. 개발 원칙

### API 호출 최소화
현재 너무 많은 Canvas API를 호출하고 있음. 리스크를 줄이기 위해:
- 필수 데이터만 조회
- 캐싱 적극 활용
- 한 번의 요청으로 필요한 데이터 모두 가져오기

### Canvas 리다이렉트 활용
복잡한 기능은 직접 구현하지 않고 Canvas 페이지로 리다이렉트:
- 프로젝트 생성/수정 → Canvas 페이지 리다이렉트 고려
- 과제 제출 → Canvas 제출 페이지 (현재 방식 유지)
- 피어 리뷰 → Canvas 피어 리뷰 페이지 (현재 방식 유지)
- SpeedGrader → Canvas SpeedGrader (현재 방식 유지)

### 단순한 해결책 우선
- React 기반 복잡한 UI 대신 ERB + 기본 JavaScript
- 100% 기능 재현보다 핵심 기능 우선
- 누락된 기능 중 Canvas 리다이렉트로 대체 가능한 것은 그대로 유지

---

## 6. 우선순위별 개선 필요 항목

### ✅ 완료된 항목
1. ~~**프로젝트 생성/수정 폼 완성**~~ (2026-01-21 완료)
   - ✅ Step Generator UI 구현
   - ✅ Group Category / Assignment Group 선택 UI
   - ✅ Step별 과제 설정 폼
   - ⚠️ 유효성 검사 (부분적)

2. ~~**프로젝트 목록 섹션 분류**~~ (2026-01-21 완료)
   - ✅ Upcoming/Current/Past/Unpublished 분류 로직
   - ✅ 섹션별 접이식 UI

3. ~~**서버 사이드 권한 체크**~~ (2026-01-22 완료)
   - ✅ `authorize_instructor!` before_action 추가
   - ✅ 학생 직접 URL 접근 차단

4. ~~**Publish/Unpublish 기능**~~ (2026-01-22 완료)
   - ✅ Save & Publish 버튼 동작
   - ✅ 수정 페이지 Publish/Unpublish 버튼
   - ✅ 역할 기반 UI 분기 (Create, 수정/삭제 버튼)

### 중간 (사용성 개선)
3. **To Do 섹션 (교수용)**
   - Task 모델 생성
   - Task CRUD API
   - Task UI

4. **피어 리뷰 선택 모달 (학생용)**
   - 여러 피어 리뷰 대상 표시
   - Canvas API 연동

5. **유효성 검사 강화**
   - 서버 사이드 날짜 순서 검증
   - 파일 확장자 제한 입력 UI

### 낮음 (선택적)
6. **자체 제출 다이얼로그**
   - Canvas 리다이렉트로 대체 가능
   - 복잡도 대비 효용 낮음

7. **반응형 UI 개선**
   - 모바일 전용 뷰

---

## 6. 파일 구조 비교

### Canvas 원본
```
ui/features/
├── hy_projects/                    # 프로젝트 목록
│   ├── index.jsx
│   └── react/
│       ├── ProjectsPage.tsx
│       ├── ProjectsDesktop.tsx
│       ├── ProjectsMobile.tsx
│       ├── ProjectTable.tsx
│       ├── utils.ts
│       └── types.ts
├── hy_project_new_v2/              # 프로젝트 생성/수정
│   ├── index.jsx
│   └── react/
│       ├── CreateProjectForm.jsx
│       ├── AssignmentForm.jsx
│       ├── SubmissionTypeSelector.jsx
│       └── ...
└── hy_project_show/                # 프로젝트 상세
    ├── index.js
    └── react/
        ├── AssignmentGroupContent.jsx
        ├── StudentAssignmentSubmissions.jsx
        └── ...

app/
├── controllers/projects_controller.rb
├── services/
│   ├── project_service.rb
│   └── project_builder.rb
└── views/projects/
    ├── index.html.erb
    ├── new.html.erb
    ├── edit.html.erb
    └── show.html.erb
```

### LTI 버전
```
app/
├── controllers/projects_controller.rb
├── helpers/projects_helper.rb
├── models/project.rb
├── services/
│   ├── project_service.rb
│   ├── project_builder.rb
│   └── canvas_api/
│       ├── client.rb
│       ├── assignments_client.rb
│       ├── submissions_client.rb
│       ├── courses_client.rb
│       ├── enrollments_client.rb
│       ├── group_categories_client.rb
│       └── assignment_groups_client.rb
└── views/projects/
    ├── index.html.erb
    ├── _project_row.html.erb
    ├── _project_list.html.erb
    ├── new.html.erb
    ├── edit.html.erb
    └── show.html.erb
```

---

## 7. 다음 작업 제안

### ✅ 완료된 단계
- ~~1단계: 프로젝트 생성/수정 폼 완성~~ (2026-01-21)
- ~~2단계: 프로젝트 목록 섹션 분류~~ (2026-01-21)

### 다음 단계: 품질 개선
1. **유효성 검사 강화**
   - 서버 사이드 날짜 순서 검증 (`ProjectBuilder` 수정)
   - 파일 확장자 제한 입력 UI 추가

2. **To Do 섹션 추가 (교수용)**
   - Task 모델 설계
   - Task CRUD API 구현
   - `show.html.erb`에 To Do UI 추가

### 선택적 개선
3. **피어 리뷰 선택 모달**
   - 학생용 여러 피어 리뷰 대상 선택 UI
   - Canvas API로 assessment_requests 조회

---

*마지막 업데이트: 2026-01-22*
