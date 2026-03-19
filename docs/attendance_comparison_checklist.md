# Canvas 원본 vs LTI Tool 출결 비교 체크리스트

> 작성일: 2026-03-18
> 최종 업데이트: 2026-03-19
> Canvas 원본 경로: `/Users/baghyeonsin/canvas-250212-docker/canvas/`
> LTI Tool 경로: `/Users/baghyeonsin/RubymineProjects/LTI_1.3_example/`

---

## 1. 데이터 모델 비교

### 1-1. 세션/설정 모델

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| ContentTag 기반 (Canvas Module Item) | ContentTag 모델 직접 사용 | AttendanceSession으로 래핑 | ✅ 동등 |
| PanoptoSetting (1:1 with ContentTag) | PanoptoSetting 모델 | VodSetting 모델 | ✅ 동등 |
| ZoomSetting (1:1 with ContentTag) | ZoomSetting 모델 | LiveSetting 모델 | ✅ 동등 |
| TeamsSetting | TeamsSetting 모델 | 미구현 | ⬜ 미적용 (Teams 미사용) |
| 주차/차시 구조 | ContextModule.weeks + Lesson.position | AttendanceSession.week + lesson_id | ✅ 동등 |
| **Auto-Sync (Canvas → Session)** | ContentTag 직접 사용 | AttendanceSyncService (멱등성 동기화) | ✅ 구현 (2026-03-19) |
| **Soft Delete** | - | deleted_at + active/deleted 스코프 | ✅ 구현 (2026-03-19) |

### 1-2. 외부 시스템 테이블

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| panopto_view_results | ✅ | ✅ | ✅ 동일 스키마 |
| panopto_view_logs | ✅ | ✅ | ✅ 동일 스키마 |
| zoom_view_results | ✅ | ✅ | ✅ 동일 스키마 |
| zoom_view_logs | ✅ | ✅ | ✅ 동일 스키마 |
| teams_view_results | ✅ | ❌ | ⬜ 미적용 (Teams 미사용) |
| teams_view_logs | ✅ | ❌ | ⬜ 미적용 (Teams 미사용) |

### 1-3. 학생 식별자

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| VOD: user_name (Canvas unique_id) | SisPseudonym.for(user, course).unique_id | LTI claim: custom_canvas_user_login_id | ✅ 동등 |
| LIVE: user_email | user.email | LTI claim: email | ✅ 동등 |

---

## 2. 비즈니스 로직 비교

### 2-1. 출결 상태 판정

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| 상태 코드 (0~4) | 0=pending, 1=absent, 2=late, 3=excused, 4=present | 동일 | ✅ |
| priority_ordered (teacher_forced 우선) | teacher_forced_change DESC, created_at DESC | 동일 | ✅ |
| VOD 자동판정: 출석마감 후 → absent | ✅ | ✅ | ✅ |
| VOD 자동판정: 지각 허용 시 지각마감 전 → late | ✅ | ✅ | ✅ |
| LIVE 자동판정: start_time+duration 후 → absent | ✅ | ✅ | ✅ |
| 레코드 없는 학생 + 마감 후 → absent 처리 | ✅ | ✅ (stats에서만) | ⚠️ 부분적 |

### 2-2. 학생 목록 조회 (핵심 차이)

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| **전체 수강생 목록 기반** | course.students_visible_to(user)로 전체 수강생 조회 | Canvas API enrolled students 조회 | ✅ 구현 |
| 레코드 없는 학생도 목록에 표시 | ✅ (미결/결석으로 자동판정) | ✅ (Canvas API 기반) | ✅ 구현 |
| 전체 학생 수 기반 통계 | enrolled 학생 수 기준 | enrolled 학생 수 기준 | ✅ 구현 |
| 식별자 사전 계산 (precompute) | precompute_student_identifiers()로 일괄 계산 | 건별 계산 | ⚠️ 성능 차이 |

### 2-3. 강제 변경 (Teacher Forced)

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| 기존 레코드 UPDATE | ✅ | ✅ | ✅ |
| 레코드 없을 때 새로 CREATE | ✅ (session_id/meeting_id는 Setting에서 가져옴) | ✅ | ✅ |
| teacher_forced_change = 1 설정 | ✅ | ✅ | ✅ |
| modified_by_user_id 기록 | ✅ (current_user.id) | ✅ (LTI claim canvas_user_id) | ✅ |
| "수정됨" 표시 | ✅ | ✅ (show.html.erb에서 badge) | ✅ |

### 2-4. 통계 계산

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| present/excused/late/absent/pending 카운트 | ✅ | ✅ | ✅ |
| 출석률 = (present + excused) / total | ✅ | ✅ | ✅ |
| 레코드 없는 학생을 absent/pending에 포함 | ✅ (enrolled 수 기준) | ✅ (enrolled 수 기준) | ✅ 구현 |
| 학생 중복 제거 (Set 기반) | ✅ | ✅ | ✅ |

---

## 3. 컨트롤러/페이지 비교

### 3-1. 페이지 구성

| Canvas 원본 페이지 | Canvas 기능 | LTI Tool 대응 | 상태 |
|-------------------|------------|--------------|------|
| **index** (세션 목록) | 세션별 통계 테이블 (주차 그룹핑) | index.html.erb | ✅ 구현 |
| **lecture_students** (세션별 학생) | 전체 수강생 목록 + 상태 드롭다운 + 체크박스 | show.html.erb | ⚠️ 부분 구현 |
| **student_lectures** (학생×세션 매트릭스) | 행=학생, 열=주차/차시, 셀=상태 | student_lectures.html.erb | ✅ 구현 (2026-03-19) |
| **student_detail** (학생별 상세) | 한 학생의 전체 세션 출결 | student_detail.html.erb | ✅ 구현 |
| **history API** (변경 이력) | 특정 학생-세션의 모든 변경 이력 | student_history API (JSON) | ✅ 구현 (2026-03-19) |
| **view_logs API** (시청 로그) | 시청 이벤트 + 세션 그루핑 (30분 gap) | student_history API에 포함 | ✅ 구현 (2026-03-19) |
| **lecture_list API** (주차별 강의) | 특정 주차/차시의 강의 목록 | ❌ 미구현 | ⬜ 불필요 (Auto-Sync로 대체) |

### 3-2. UI 비교 상세

#### index (세션 목록)

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| 주차별 그룹핑 | ✅ | ✅ | ✅ |
| 테이블 형식 | ✅ | ✅ | ✅ |
| 교수: 출석/지각/결석/미결 통계 | ✅ | ✅ | ✅ |
| 학생: 본인 출결 상태 | ✅ | ✅ | ✅ |
| 세션 자동 동기화 (Auto-Sync) | - (ContentTag 직접 사용) | ✅ AttendanceSyncService | ✅ 구현 (2026-03-19) |
| 코스 헤더 (코드/이름/교수) | ✅ | ✅ | ✅ 구현 (2026-03-19) |
| 탭 네비게이션 (By Content / By Student) | ✅ | ✅ | ✅ 구현 (2026-03-19) |

#### lecture_students (세션별 학생 목록) → show.html.erb

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| **전체 수강생 표시** | ✅ (enrolled 전원) | ✅ (Canvas API enrolled) | ✅ 구현 |
| 테이블 형식 | ✅ | ✅ | ✅ |
| 상태 드롭다운 (강제 변경) | ✅ (inline select) | ✅ (select + AJAX) | ✅ |
| "수정됨" 표시 | ✅ | ✅ | ✅ |
| 체크박스 (행 선택) | ✅ | ❌ | ❌ 미적용 |
| 엑셀 다운로드 | ✅ | ❌ | ❌ 미적용 |
| 히스토리 모달 | ✅ (AttendanceHistoryModal) | ❌ | ❌ 미적용 |
| 시청 로그 보기 | ✅ (ViewLogsService) | ❌ | ❌ 미적용 |
| 검색/필터 | ✅ | ❌ | ❌ 미적용 |
| 정렬 | ✅ | ❌ | ❌ 미적용 |

#### student_lectures (학생×세션 매트릭스) → student_lectures.html.erb

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| 행=학생, 열=주차/차시 매트릭스 | ✅ (React StudentLectures.jsx) | ✅ (ERB + Sticky Table) | ✅ 구현 (2026-03-19) |
| 코스 헤더 (코드/이름/교수) | ✅ | ✅ | ✅ 구현 (2026-03-19) |
| 탭 네비게이션 | ✅ | ✅ | ✅ 구현 (2026-03-19) |
| Student Number 컬럼 | ✅ | ✅ | ✅ 구현 (2026-03-19) |
| 통계 컬럼 (Present/Late/Absent/Pending) | ✅ | ✅ | ✅ 구현 (2026-03-19) |
| 체크박스 (행 선택) | ✅ | ✅ (전체선택 포함) | ✅ 구현 (2026-03-19) |
| 엑셀 다운로드 (Download Excel) | ✅ | ✅ (CSV with BOM) | ✅ 구현 (2026-03-19) |
| 이름 정렬 (Name ↕) | ✅ | ✅ (JS 클라이언트 정렬) | ✅ 구현 (2026-03-19) |
| 셀 클릭 → 히스토리 모달 | ✅ (React Modal) | ✅ (JS Modal + JSON API) | ✅ 구현 (2026-03-19) |
| 히스토리: 출결 판정 이력 | ✅ | ✅ (결과 변경 이력 + 수동변경 표시) | ✅ 구현 (2026-03-19) |
| 히스토리: 시청/참여 로그 | ✅ (ViewLogsService) | ✅ (VOD: 시청로그, LIVE: 참여로그) | ✅ 구현 (2026-03-19) |
| 히스토리: 총 시청/참여 시간 | ✅ | ✅ | ✅ 구현 (2026-03-19) |
| 스크롤 가능 테이블 (TableWrapper) | ✅ (React 컴포넌트) | ✅ (CSS overflow + sticky) | ✅ 구현 (2026-03-19) |
| 레슨 레벨 우선 상태 (absent > late > present > pending) | ✅ | ❌ | ❌ 미적용 |

#### student_detail (학생별 상세)

| 항목 | Canvas 원본 | LTI Tool | 상태 |
|------|------------|----------|------|
| 주차별 출결 카드 | ✅ | ✅ (카드 형태) | ✅ |
| 통계 요약 | ✅ | ✅ | ✅ |
| 상태 배지 | ✅ | ✅ | ✅ |
| 히스토리 보기 | ✅ | ❌ | ❌ 미적용 |
| 시청 로그 보기 | ✅ | ❌ | ❌ 미적용 |

---

## 4. 기술 구현 비교

### 4-1. 프론트엔드

| 항목 | Canvas 원본 | LTI Tool | 비고 |
|------|------------|----------|------|
| 렌더링 방식 | React (JSX) + js_env | 서버 사이드 ERB | 설계 차이 (문제 아님) |
| 상태 관리 | React useState/useEffect | 페이지 새로고침 | |
| API 호출 | fetch() + JSON API | form submit + AJAX (show만) | |
| 모달 | React 컴포넌트 (AttendanceHistoryModal) | JS + DOM 모달 | ✅ 구현 (2026-03-19) |
| 테이블 스크롤 | TableWrapper 컴포넌트 | CSS overflow + sticky columns | ✅ 구현 (2026-03-19) |

### 4-2. 서비스 구조

| Canvas 원본 서비스 | 기능 | LTI Tool 대응 | 상태 |
|-------------------|------|--------------|------|
| ListService | 세션 목록 + 통계 | AttendanceService#sessions_with_statistics | ✅ |
| LectureStudentsService | 세션별 전체 학생 | AttendanceService#session_students | ✅ 구현 |
| StudentLecturesService | 학생×세션 매트릭스 | AttendanceService#student_lectures_matrix | ✅ 구현 (2026-03-19) |
| StudentDetailService | 학생별 상세 | AttendanceService#student_attendance | ✅ |
| StatsCalculator | 통계 + 자동판정 | AttendanceStatsCalculator | ✅ |
| UpdateService | 강제 변경 (upsert) | AttendanceUpdateService | ✅ |
| HistoryService | 변경 이력 조회 | student_history API (controller) | ✅ 구현 (2026-03-19) |
| ViewLogsService | 시청 로그 + 세션 그루핑 | student_history API에 포함 | ✅ 구현 (2026-03-19) |
| SyncService | - | AttendanceSyncService (Auto-Sync) | ✅ 구현 (2026-03-19) |
| QueryHelper | 일괄 조회 + 인덱싱 | AttendanceQueryHelper | ✅ |

---

## 5. 우선순위별 미적용 항목 정리

### P0 - 필수 (기능 결함) → ✅ 모두 완료

| # | 항목 | 설명 | 상태 |
|---|------|------|------|
| 1 | ~~전체 수강생 목록~~ | Canvas API enrolled students 조회 구현 | ✅ 완료 |
| 2 | ~~통계 기준 보정~~ | enrolled 학생 수 기준 통계 계산 | ✅ 완료 |

### P1 - 중요 (원본 핵심 기능)

| # | 항목 | 설명 | 상태 |
|---|------|------|------|
| 3 | ~~학생×세션 매트릭스 뷰~~ | student_lectures.html.erb 구현 완료 | ✅ 완료 (2026-03-19) |
| 4 | ~~변경 이력 (History)~~ | student_history JSON API + 모달 UI | ✅ 완료 (2026-03-19) |
| 5 | ~~시청 로그 (View Logs)~~ | student_history API에 VOD/LIVE 로그 포함 | ✅ 완료 (2026-03-19) |
| 6 | **레슨 레벨 우선 상태** | 한 차시에 여러 강의 있을 때 absent > late > present > pending 우선순위 | ❌ 미적용 |

### P2 - 개선 (편의 기능)

| # | 항목 | 설명 | 상태 |
|---|------|------|------|
| 7 | ~~엑셀 다운로드~~ | student_lectures_excel (CSV with BOM) | ✅ 완료 (2026-03-19) |
| 8 | ~~체크박스 행 선택 (student_lectures)~~ | 전체선택 + 행별 체크박스 | ✅ 완료 (2026-03-19) |
| 9 | **검색/필터** | 학생 이름 검색, 상태별 필터링 | ❌ 미적용 |
| 10 | ~~정렬 (student_lectures)~~ | Name 컬럼 클릭 오름/내림차순 정렬 | ✅ 완료 (2026-03-19) |
| 11 | ~~히스토리 모달 (student_lectures)~~ | 셀 클릭 → 출결 판정 이력 + 시청/참여 로그 모달 | ✅ 완료 (2026-03-19) |
| 8b | **체크박스 행 선택 (show)** | lecture_students(show) 페이지에도 체크박스 필요 | ❌ 미적용 |
| 7b | **엑셀 다운로드 (show)** | lecture_students(show) 페이지에도 엑셀 다운로드 필요 | ❌ 미적용 |
| 9b | **검색/필터 (show)** | lecture_students(show) 페이지 학생 검색 | ❌ 미적용 |
| 10b | **정렬 (show)** | lecture_students(show) 페이지 이름/상태 정렬 | ❌ 미적용 |
| 11b | **히스토리 모달 (show)** | lecture_students(show) 페이지에서도 히스토리 보기 | ❌ 미적용 |
| 12 | **히스토리/로그 (student_detail)** | 학생 상세 페이지에서 히스토리/시청 로그 보기 | ❌ 미적용 |

### P3 - 향후 (확장)

| # | 항목 | 설명 | 난이도 |
|---|------|------|--------|
| 13 | Canvas AGS 연동 | 출결 → Canvas 성적표 자동 반영 | 높음 |
| 14 | Teams 지원 | TeamsViewResult/Log + TeamsSetting | 중간 |
| 15 | 실시간 업데이트 | WebSocket/polling으로 실시간 출결 변동 | 높음 |
| 16 | 페이지네이션 | 대규모 수강생 처리 | 낮음 |

---

## 6. 2026-03-19 작업 이력

### 완료 항목
1. **Auto-Sync 시스템** - 세션 생성/삭제를 Canvas Module Items와 자동 동기화 (멱등성 5시나리오: CREATE/SKIP/RESTORE/SOFT DELETE/SKIP deleted)
2. **코스 헤더** - 코스코드(context_label) + 코스명(context_title) + 담당교수(instructor_names) Canvas API 연동
3. **탭 네비게이션** - By Content / By Student 탭 UI
4. **student_lectures 매트릭스 뷰 완성**:
   - 학생×세션 매트릭스 테이블 (sticky columns)
   - Student Number 컬럼
   - 체크박스 (전체선택 + 행별)
   - Download Excel (CSV with BOM)
   - Name 정렬 (클라이언트 JS)
   - 셀 클릭 → 히스토리 모달 (student_history JSON API)
5. **student_history API** - 출결 판정 이력 + 시청/참여 로그 + 총 시청/참여 시간
6. **Soft Delete** - deleted_at 기반 soft delete + restore
7. **배경색 투명화** - body background transparent (Canvas iframe 통합)
8. **불필요 UI 제거** - 수동 Create/Bulk Create/Delete 버튼 제거 (Auto-Sync로 대체)

### 남은 항목 (페이지별 정리)
- **show (lecture_students)**: 체크박스, 엑셀 다운로드, 히스토리 모달, 검색/필터, 정렬
- **student_detail**: 히스토리/시청 로그 보기
- **student_lectures**: 레슨 레벨 우선 상태 (P1 #6)
- **공통**: 검색/필터

---

## 7. 요약

### 잘 된 것
- 기본 데이터 모델 (세션/설정/외부 테이블) 구조 동일
- 출결 상태 코드 및 자동판정 로직 정확히 포팅
- 강제 변경 (teacher forced) 로직 동일
- Auto-Sync: Canvas Module Items ↔ AttendanceSession 자동 동기화 (멱등성)
- student_lectures 매트릭스 뷰 완전 구현 (체크박스, Excel, 정렬, 히스토리 모달)
- 코스 헤더 (코스코드 + 코스명 + 교수명) Canvas API 연동

### 핵심 차이점 (향후 작업)
1. **show (lecture_students) 페이지** - 체크박스/엑셀/히스토리/검색/정렬 미구현
2. **student_detail 페이지** - 히스토리/시청 로그 미구현
3. **레슨 레벨 우선 상태** - 한 차시에 여러 강의 시 우선순위 로직 미적용
