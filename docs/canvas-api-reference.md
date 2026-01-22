# Canvas API Reference

이 문서는 LTI 프로젝트에서 사용하는 Canvas API의 레퍼런스입니다.

---

## 기본 정보

### Base URL
```
https://{canvas-domain}/api/v1
```

### 인증
```
Authorization: Bearer {access_token}
```

### 응답 형식
- JSON 형식
- 타임스탬프: ISO 8601 (UTC) `YYYY-MM-DDTHH:MM:SSZ`
- ID: 64비트 정수 (문자열 강제: `Accept: application/json+canvas-string-ids`)

### 페이지네이션
- `per_page` 파라미터로 페이지당 항목 수 지정
- Link 헤더에 다음/이전 페이지 URL 포함

---

## 1. Assignments API

### 목록 조회
```
GET /api/v1/courses/:course_id/assignments
```

**파라미터:**
| 파라미터 | 설명 |
|---------|------|
| `include[]` | submission, assignment_visibility, all_dates, overrides |
| `search_term` | 과제명 검색 |
| `bucket` | past, overdue, undated, ungraded, unsubmitted, upcoming, future |
| `order_by` | position, name, due_at |

### 상세 조회
```
GET /api/v1/courses/:course_id/assignments/:id
```

### 생성
```
POST /api/v1/courses/:course_id/assignments
```

**주요 파라미터:**
| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `assignment[name]` | O | 과제명 |
| `assignment[submission_types][]` | - | online_upload, online_text_entry, online_url, media_recording, none, on_paper |
| `assignment[points_possible]` | - | 배점 |
| `assignment[due_at]` | - | 마감일 (ISO 8601) |
| `assignment[unlock_at]` | - | 시작일 (ISO 8601) |
| `assignment[lock_at]` | - | 종료일 (ISO 8601) |
| `assignment[grading_type]` | - | points, pass_fail, percent, letter_grade, gpa_scale, not_graded |
| `assignment[assignment_group_id]` | - | 과제 그룹 ID |
| `assignment[peer_reviews]` | - | 피어 리뷰 활성화 |
| `assignment[automatic_peer_reviews]` | - | 자동 피어 리뷰 배정 |
| `assignment[peer_review_count]` | - | 피어 리뷰 수 |
| `assignment[group_category_id]` | - | 그룹 카테고리 ID (그룹 과제) |
| `assignment[grade_group_students_individually]` | - | 그룹 과제에서 개별 채점 |
| `assignment[allowed_extensions][]` | - | 허용 파일 확장자 |
| `assignment[allowed_attempts]` | - | 제출 허용 횟수 (-1: 무제한) |
| `assignment[published]` | - | 공개 여부 |

### 수정
```
PUT /api/v1/courses/:course_id/assignments/:id
```
- 생성과 동일한 파라미터 사용
- 학생 제출이 있으면 `submission_types` 수정 불가

### 삭제
```
DELETE /api/v1/courses/:course_id/assignments/:id
```

### Assignment 응답 객체
```json
{
  "id": 123,
  "name": "과제명",
  "description": "설명 (HTML)",
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "due_at": "2024-01-15T23:59:59Z",
  "lock_at": "2024-01-16T23:59:59Z",
  "unlock_at": "2024-01-01T00:00:00Z",
  "course_id": 456,
  "assignment_group_id": 789,
  "points_possible": 100,
  "grading_type": "points",
  "submission_types": ["online_upload"],
  "allowed_extensions": ["pdf", "docx"],
  "allowed_attempts": -1,
  "has_submitted_submissions": true,
  "published": true,
  "peer_reviews": false,
  "group_category_id": null,
  "grade_group_students_individually": false
}
```

---

## 2. Submissions API

### 목록 조회
```
GET /api/v1/courses/:course_id/assignments/:assignment_id/submissions
```

**파라미터:**
| 파라미터 | 설명 |
|---------|------|
| `include[]` | submission_history, submission_comments, rubric_assessment, assignment, user |
| `grouped` | true면 그룹별로 응답 |

### 상세 조회
```
GET /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id
```

### 제출 (학생)
```
POST /api/v1/courses/:course_id/assignments/:assignment_id/submissions
```

**파라미터:**
| 파라미터 | 필수 | 설명 |
|---------|------|------|
| `submission[submission_type]` | O | online_text_entry, online_url, online_upload, media_recording |
| `submission[body]` | - | 텍스트 내용 (online_text_entry) |
| `submission[url]` | - | URL (online_url) |
| `submission[file_ids][]` | - | 업로드된 파일 ID 배열 (online_upload) |

### 채점 (교수)
```
PUT /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id
```

**파라미터:**
| 파라미터 | 설명 |
|---------|------|
| `submission[posted_grade]` | 점수 (숫자, %, 등급, pass/fail) |
| `submission[excuse]` | 면제 여부 |
| `comment[text_comment]` | 텍스트 피드백 |

### 제출 통계
```
GET /api/v1/courses/:course_id/assignments/:assignment_id/submission_summary
```

**응답:**
```json
{
  "graded": 5,
  "ungraded": 10,
  "not_submitted": 42
}
```

### Submission 응답 객체
```json
{
  "assignment_id": 123,
  "user_id": 456,
  "score": 85.5,
  "grade": "B+",
  "submitted_at": "2024-01-10T14:30:00Z",
  "graded_at": "2024-01-12T10:00:00Z",
  "grader_id": 789,
  "workflow_state": "graded",
  "late": false,
  "missing": false,
  "excused": false,
  "submission_type": "online_upload",
  "attempt": 1
}
```

**workflow_state 값:**
- `unsubmitted` - 미제출
- `submitted` - 제출됨
- `graded` - 채점됨
- `pending_review` - 검토 대기

---

## 3. Enrollments API

### 목록 조회
```
GET /api/v1/courses/:course_id/enrollments
```

**파라미터:**
| 파라미터 | 설명 |
|---------|------|
| `type[]` | StudentEnrollment, TeacherEnrollment, TaEnrollment, DesignerEnrollment, ObserverEnrollment |
| `role[]` | 커스텀 역할명 |
| `state[]` | active, invited, creation_pending, deleted, rejected, completed, inactive |
| `include[]` | avatar_url, group_ids, uuid |

### Enrollment 응답 객체
```json
{
  "id": 123,
  "course_id": 456,
  "user_id": 789,
  "type": "StudentEnrollment",
  "role": "StudentEnrollment",
  "role_id": 1,
  "enrollment_state": "active",
  "user": {
    "id": 789,
    "name": "학생 이름",
    "sortable_name": "이름, 학생"
  }
}
```

---

## 4. Groups API

### 코스의 그룹 목록
```
GET /api/v1/courses/:course_id/groups
```

**파라미터:**
| 파라미터 | 설명 |
|---------|------|
| `only_own_groups` | 자신이 속한 그룹만 |
| `include[]` | tabs |

### 그룹 상세
```
GET /api/v1/groups/:group_id
```

### 그룹 멤버 목록
```
GET /api/v1/groups/:group_id/memberships
```

### 그룹 사용자 목록
```
GET /api/v1/groups/:group_id/users
```

### Group 응답 객체
```json
{
  "id": 123,
  "name": "그룹명",
  "description": "설명",
  "members_count": 5,
  "group_category_id": 456,
  "context_type": "Course",
  "course_id": 789
}
```

---

## 5. Group Categories API

### 코스의 그룹 카테고리 목록
```
GET /api/v1/courses/:course_id/group_categories
```

### 그룹 카테고리 상세
```
GET /api/v1/group_categories/:group_category_id
```

### 그룹 카테고리의 그룹 목록
```
GET /api/v1/group_categories/:group_category_id/groups
```

### GroupCategory 응답 객체
```json
{
  "id": 123,
  "name": "카테고리명",
  "role": null,
  "self_signup": "enabled",
  "auto_leader": "first",
  "context_type": "Course",
  "course_id": 456,
  "group_limit": 5,
  "groups_count": 10
}
```

---

## 6. Assignment Groups API

### 목록 조회
```
GET /api/v1/courses/:course_id/assignment_groups
```

**파라미터:**
| 파라미터 | 설명 |
|---------|------|
| `include[]` | assignments, discussion_topic, assignment_visibility |
| `exclude_assignment_submission_types[]` | 특정 submission_type 제외 |

### AssignmentGroup 응답 객체
```json
{
  "id": 123,
  "name": "과제 그룹명",
  "position": 1,
  "group_weight": 20.0,
  "assignments": []
}
```

---

## 7. Courses API

### 코스 상세
```
GET /api/v1/courses/:id
```

### 코스 사용자 목록
```
GET /api/v1/courses/:course_id/users
```

**파라미터:**
| 파라미터 | 설명 |
|---------|------|
| `enrollment_type[]` | teacher, student, ta, observer, designer |
| `include[]` | email, enrollments, avatar_url |

---

## 8. 파일 업로드

Canvas 파일 업로드는 3단계 프로세스:

### Step 1: 업로드 URL 요청
```
POST /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id/files
```

**파라미터:**
```json
{
  "name": "filename.pdf",
  "size": 12345,
  "content_type": "application/pdf"
}
```

**응답:**
```json
{
  "upload_url": "https://...",
  "upload_params": { ... }
}
```

### Step 2: 파일 업로드
`upload_url`로 파일 데이터와 `upload_params` POST

### Step 3: 업로드 확인
응답의 `location` 헤더나 `id`로 파일 ID 획득

---

## 자주 사용하는 API 조합

### 프로젝트 목록 페이지
1. `GET /courses/:id/assignments` - 과제 목록
2. `GET /courses/:id/assignments/:id/submission_summary` - 제출 통계

### 프로젝트 상세 페이지 (교수)
1. `GET /courses/:id/assignments/:id` - 과제 상세
2. `GET /courses/:id/group_categories/:id/groups` - 그룹 목록
3. `GET /groups/:id/memberships` - 그룹 멤버
4. `GET /courses/:id/assignments/:id/submissions` - 제출물 목록

### 프로젝트 상세 페이지 (학생)
1. `GET /courses/:id/assignments/:id` - 과제 상세
2. `GET /courses/:id/assignments/:id/submissions/:user_id` - 내 제출물

---

## 에러 응답

### 401 Unauthorized
```json
{
  "status": "unauthorized",
  "errors": [{"message": "Invalid access token."}]
}
```

### 403 Forbidden
```json
{
  "status": "forbidden",
  "errors": [{"message": "user not authorized to perform that action"}]
}
```

### 404 Not Found
```json
{
  "errors": [{"message": "The specified resource does not exist"}]
}
```

### 422 Unprocessable Entity
```json
{
  "errors": {
    "name": [{"type": "required", "message": "name is required"}]
  }
}
```

---

## Rate Limiting

- 요청 제한: 초당/분당 제한 있음
- 헤더로 확인:
  - `X-Rate-Limit-Remaining`: 남은 요청 수
  - `X-Request-Cost`: 현재 요청 비용
- 429 응답 시 재시도 필요

---

*참고: https://canvas.instructure.com/doc/api/*

*마지막 업데이트: 2026-01-21*
