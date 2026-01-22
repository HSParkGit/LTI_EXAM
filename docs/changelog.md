# Changelog

이 프로젝트의 주요 변경 사항을 기록합니다.

---

## [2026-01-22]

### 추가
- **서버 사이드 권한 체크** (`projects_controller.rb`)
  - `authorize_instructor!` before_action 추가
  - new, create, edit, update, destroy 액션에 교수 권한 필수
  - 학생이 직접 URL 접근 시 차단

- **Publish/Unpublish 기능** (`new.html.erb`, `edit.html.erb`, `project_builder.rb`)
  - 생성 페이지: Save & Publish 버튼 동작 구현
  - 수정 페이지: 현재 상태에 따라 Publish/Unpublish 버튼 표시
  - `unpublish_assignment` 메서드 추가

### 수정
- **역할 기반 UI 분기** (`index.html.erb`, `_project_row.html.erb`)
  - Create 버튼: instructor만 표시
  - 드롭다운 메뉴(수정/삭제): instructor만 표시
  - Empty state 생성 링크: instructor만 표시

- **프로젝트 섹션 분류 버그 수정** (`project_service.rb`)
  - `filter_assignments_for_project`에서 ID 타입 불일치 문제 해결
  - Canvas API의 assignment ID(정수)와 project.assignment_ids(문자열) 비교 시 `to_s` 변환 추가
  - `get_published_status`에서 `workflow_state` 또는 `published` 필드 모두 확인

---

## [2026-01-21]

### 추가
- **프로젝트 생성/수정 폼 완성** (`new.html.erb`, `edit.html.erb`)
  - Step Generator UI (JavaScript 동적 추가/삭제)
  - Group Category / Assignment Group 선택 (Canvas API 연동)
  - Step별 과제 설정 폼 (제목, 설명, 배점, 제출 타입, 날짜 등)

- **프로젝트 목록 섹션 분류** (`project_service.rb`, `index.html.erb`)
  - `classify_projects` 메서드로 4개 섹션 분류
  - Upcoming: 모든 Step 시작일이 미래
  - Current: 1개 이상 Step이 진행 중
  - Past: 모든 Step 마감일이 과거
  - Unpublished: 비공개 프로젝트 (교수만 표시)

---

*이전 변경 사항은 git log를 참조하세요.*
