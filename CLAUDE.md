# LTI 1.3 Example Project

## 프로젝트 개요
Canvas LMS용 LTI 1.3 Tool. 두 가지 기능 제공:
1. **Projects** - 프로젝트 기반 과제 관리
2. **Attendance** - 출결 관리 (VOD/LIVE)

## 기술 스택
- Ruby on Rails 7.1
- PostgreSQL
- LTI 1.3 (OIDC + JWT)

## 아키텍처

### LTI Launch 흐름
```
Canvas → /lti/login (OIDC) → /lti/launch?tool=xxx → 해당 Tool로 redirect
```

### Tool 분기
- `?tool=projects` → `/projects`
- `?tool=attendance` → `/attendance`

### 공유 모델
- `LtiPlatform` - Canvas 인스턴스 (iss, client_id, secrets)
- `LtiContext` - Canvas 코스 (context_id)

---

## Attendance 기능 (2026-02-27 아키텍처 재설계)

### 핵심 설계 원칙
- **외부 시스템 데이터 주입**: Panopto/Zoom 출결 시스템이 직접 DB에 INSERT
- **Canvas와 동일한 로직**: Canvas 원본 소스 기반 포팅
- **멀티 학교 지원**: content_tag_id가 전역 유니크하여 학교 구분 불필요

### 모델 구조
```
LtiContext
└── AttendanceSession (주차/차시 기반)
    ├── VodSetting (1:1) - Panopto VOD 설정
    └── LiveSetting (1:1) - Zoom LIVE 설정

외부 시스템 테이블 (content_tag_id로 연결):
├── panopto_view_logs - VOD 시청 로그
├── panopto_view_results - VOD 출결 결과
├── zoom_view_logs - LIVE 참여 로그
└── zoom_view_results - LIVE 출결 결과
```

### 학생 식별자
| 타입 | 식별자 | LTI Claim |
|------|--------|-----------|
| VOD (Panopto) | user_name (Canvas unique_id) | custom_canvas_user_login_id |
| LIVE (Zoom) | user_email | email |

### 출결 상태 코드
| 코드 | 상태 | 설명 |
|------|------|------|
| 0 | pending | 미결 |
| 1 | absent | 결석 |
| 2 | late | 지각 |
| 3 | excused | 공결 |
| 4 | present | 출석 |

### 파일 위치
```
app/models/
├── attendance_session.rb    # 출결 세션 (주차/차시)
├── vod_setting.rb          # VOD 설정
├── live_setting.rb         # LIVE 설정
├── panopto_view_log.rb     # Panopto 시청 로그
├── panopto_view_result.rb  # Panopto 출결 결과
├── zoom_view_log.rb        # Zoom 참여 로그
└── zoom_view_result.rb     # Zoom 출결 결과

app/services/
├── attendance_service.rb           # 메인 서비스
├── attendance_update_service.rb    # 강제 변경 서비스
├── attendance_stats_calculator.rb  # 통계/판정 계산
└── attendance_query_helper.rb      # 조회 헬퍼

app/controllers/
└── attendance_controller.rb

app/helpers/
└── attendance_helper.rb

app/views/attendance/
├── index.html.erb
├── show.html.erb
├── student_detail.html.erb
├── new.html.erb
├── edit.html.erb
├── _form.html.erb
├── _vod_setting_fields.html.erb
└── _live_setting_fields.html.erb
```

### 데이터 흐름
```
[외부 시스템 데이터 주입]
Panopto/Zoom 출결 시스템 → DB 직접 INSERT
├── panopto_view_logs (시청 이벤트)
├── panopto_view_results (출결 결과)
├── zoom_view_logs (참여 이벤트)
└── zoom_view_results (출결 결과)

[LTI Tool 출결 관리]
Canvas → LTI Launch → AttendanceController
├── 교수: 세션 생성/수정, 학생 출결 조회/강제변경
└── 학생: 본인 출결 현황 조회
```

### 기간 기반 자동 판정 (resolve_pending_status)
- **VOD**: attendance_finish_at 이후 → absent 또는 late (tardiness 허용 시)
- **LIVE**: start_time + duration 이후 → absent

### 우선순위 처리
- `teacher_forced_change = 1`인 레코드가 최우선
- 이후 created_at DESC 순서

### Canvas 연동
- `content_tag_id`: Canvas Module Item과 매핑 (전역 유니크)
- Canvas API: `CanvasApi::ModulesClient`로 External Tool 아이템 조회

---

## 테스트 방법

### 서버 실행
```bash
bin/rails server
```

### Canvas External Tool 설정
- Target Link URI: `https://your-domain/lti/launch?tool=attendance`
- Custom Parameters:
  ```
  canvas_user_login_id=$Canvas.user.loginId
  canvas_user_id=$Canvas.user.id
  ```

### 테스트 데이터 생성 (rails console)
```ruby
# 세션 생성
ctx = LtiContext.first
session = ctx.attendance_sessions.create!(
  week: 1, lesson_id: 1, title: '1주차 OT',
  attendance_type: 'vod', content_tag_id: 12345
)
session.create_vod_setting!(
  session_id: 'panopto-uuid-here',
  allow_attendance: true, percent_required: 80,
  unlock_at: 1.day.ago, attendance_finish_at: 1.day.from_now
)

# 외부 시스템 데이터 시뮬레이션 (실제로는 외부 시스템이 INSERT)
PanoptoViewResult.create!(
  content_tag_id: 12345,
  session_id: 'panopto-uuid-here',
  user_id: SecureRandom.uuid,
  user_name: 'student001',  # Canvas unique_id
  attendance_state: 4       # present
)
```

---

## 마이그레이션

### 외부 시스템 테이블 (스키마 변경 불가)
```
db/migrate/
├── 20260227100001_create_panopto_view_logs.rb
├── 20260227100002_create_panopto_view_results.rb
├── 20260227100003_create_zoom_view_logs.rb
└── 20260227100004_create_zoom_view_results.rb
```

### 내부 관리 테이블
```
db/migrate/
├── 20260220100001_create_attendance_sessions.rb
├── 20260220100002_create_vod_settings.rb
└── 20260220100003_create_live_settings.rb
```

---

## 미구현 (향후 확장)
- Canvas AGS 연동 (성적표 반영)
- 출결 리포트 다운로드 (Excel/CSV)
- 로그 테이블 데이터 활용 (시청률/참여율 표시)

---

## 최근 작업 이력
- **2026-02-27**: Canvas 원본 기반 아키텍처 재설계
  - panopto_view_results / zoom_view_results 테이블 구조로 변경
  - 학생 식별자: user_name (Panopto) / user_email (Zoom)
  - AttendanceStatsCalculator: 기간 기반 자동 판정 로직 포팅
  - 멀티 학교 지원 (content_tag_id 전역 유니크)
- **2024-02-20**: Attendance 기능 초기 구현
