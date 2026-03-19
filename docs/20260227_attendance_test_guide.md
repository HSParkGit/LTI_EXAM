# Attendance 기능 테스트 가이드

> 작성일: 2026-02-27
> Canvas 원본 기반 아키텍처 재설계 후 테스트 가이드

---

## 목차
1. [사전 준비](#1-사전-준비)
2. [LTI Platform 등록](#2-lti-platform-등록)
3. [Canvas External Tool 설정](#3-canvas-external-tool-설정)
4. [서버 실행 및 확인](#4-서버-실행-및-확인)
5. [테스트 시나리오](#5-테스트-시나리오)
6. [테스트 데이터 생성](#6-테스트-데이터-생성)
7. [트러블슈팅](#7-트러블슈팅)

---

## 1. 사전 준비

### 1.1 필수 요구사항
- Ruby 3.x
- Rails 7.1
- PostgreSQL
- Canvas LMS 인스턴스 (관리자 권한 필요)

### 1.2 데이터베이스 마이그레이션
```bash
cd /path/to/LTI_1.3_example
bin/rails db:migrate
```

### 1.3 마이그레이션 확인
```bash
bin/rails db:migrate:status
```

다음 테이블들이 생성되어야 함:
- `lti_platforms` - LTI Platform 설정
- `lti_contexts` - Canvas 코스 정보
- `attendance_sessions` - 출결 세션
- `vod_settings` - VOD 설정
- `live_settings` - LIVE 설정
- `panopto_view_logs` - Panopto 시청 로그
- `panopto_view_results` - Panopto 출결 결과
- `zoom_view_logs` - Zoom 참여 로그
- `zoom_view_results` - Zoom 출결 결과

---

## 2. LTI Platform 등록

### 2.1 Canvas에서 Developer Key 생성

1. Canvas Admin 접속
2. **Admin** → **Developer Keys** → **+ Developer Key** → **+ LTI Key**

#### LTI Key 설정값

| 설정 항목 | 값 |
|----------|-----|
| Key Name | `LTI Tool - Attendance` |
| Redirect URIs | `https://your-domain/lti/launch` |
| Target Link URI | `https://your-domain/lti/launch?tool=attendance` |
| OpenID Connect Initiation URL | `https://your-domain/lti/login` |
| JWK Method | Public JWK URL |
| Public JWK URL | `https://your-domain/.well-known/jwks.json` |

#### LTI Advantage Services (활성화)
- [x] Can create and view assignment data in the gradebook
- [x] Can view assignment data in the gradebook
- [x] Can view submission data for all users
- [x] Can create and update submission results
- [x] Can retrieve user data associated with the context

#### Additional Settings
- **Privacy Level**: Public
- **Placements**: Course Navigation, Assignment Selection

3. **Save** 후 **Client ID** 복사 (숫자 형태: `10000000000001`)

4. Developer Key를 **ON** 상태로 변경

### 2.2 LTI Platform 관리 페이지에서 등록

1. LTI Tool 서버 실행
```bash
bin/rails server
```

2. 브라우저에서 `/admin/lti_platforms` 접속

3. **+ New Platform** 클릭 후 다음 정보 입력:

| 필드 | 값 | 예시 |
|------|-----|------|
| ISS (Issuer) | Canvas 인스턴스 URL | `https://canvas.school.ac.kr` |
| Client ID | Developer Key에서 복사한 ID | `10000000000001` |
| Auth URL | `{canvas_url}/api/lti/authorize_redirect` | `https://canvas.school.ac.kr/api/lti/authorize_redirect` |
| Token URL | `{canvas_url}/login/oauth2/token` | `https://canvas.school.ac.kr/login/oauth2/token` |
| JWKS URL | `{canvas_url}/api/lti/security/jwks` | `https://canvas.school.ac.kr/api/lti/security/jwks` |
| Canvas URL | Canvas 인스턴스 URL (API 호출용) | `https://canvas.school.ac.kr` |

4. **Save** 클릭

### 2.3 멀티 학교 지원
여러 학교(Canvas 인스턴스)를 지원하려면 각 학교별로 위 과정을 반복합니다.
`content_tag_id`가 전역 유니크하므로 학교 간 데이터 충돌은 없습니다.

---

## 3. Canvas External Tool 설정

### 3.1 코스에 External Tool 추가

1. Canvas 코스 접속
2. **Settings** → **Apps** → **+ App**
3. **Configuration Type**: By Client ID
4. **Client ID**: Developer Key에서 복사한 ID 입력
5. **Submit** → **Install**

### 3.2 Custom Parameters 설정 (중요!)

External Tool 설정에서 Custom Fields 추가:

```
canvas_user_login_id=$Canvas.user.loginId
canvas_user_id=$Canvas.user.id
```

이 설정이 없으면 학생 식별이 불가능합니다.

### 3.3 Course Navigation에서 확인
코스 좌측 메뉴에 "Attendance" 또는 설정한 Tool 이름이 표시되어야 합니다.

---

## 4. 서버 실행 및 확인

### 4.1 서버 실행
```bash
bin/rails server -b 0.0.0.0 -p 3000
```

### 4.2 기본 동작 확인

#### 헬스체크
```bash
curl http://localhost:3000/up
```
응답: `200 OK`

#### LTI Platform 목록
브라우저에서 `http://localhost:3000/admin/lti_platforms` 접속
→ 등록한 Platform 목록 확인

### 4.3 로그 모니터링
```bash
tail -f log/development.log
```

---

## 5. 테스트 시나리오

### 5.1 시나리오 A: 교수 - 출결 세션 생성

#### 사전 조건
- Canvas에 교수 계정으로 로그인
- 테스트 코스에 Instructor 역할로 등록

#### 테스트 단계

| 단계 | 액션 | 예상 결과 |
|------|------|----------|
| 1 | Canvas 코스 → Attendance 메뉴 클릭 | LTI Launch 성공, 출결 목록 페이지 표시 |
| 2 | "+ Create Session" 버튼 클릭 | 세션 생성 폼 표시 |
| 3 | 주차: 1, 차시: 1, 제목: "1주차 OT", 유형: VOD 선택 | 폼 입력 완료 |
| 4 | VOD 설정: 필요 진도율 80%, 출석 마감일 설정 | 설정 입력 완료 |
| 5 | Canvas 연동: Module Item 선택 (있는 경우) | content_tag_id 매핑 |
| 6 | "저장" 버튼 클릭 | 세션 생성 완료, 상세 페이지로 이동 |

#### 확인 사항
- [ ] 세션이 목록에 표시됨
- [ ] 주차별 그룹핑 정상 작동
- [ ] VOD/LIVE 배지 정상 표시

### 5.2 시나리오 B: 교수 - 학생 출결 조회

#### 사전 조건
- 출결 세션이 생성되어 있음
- 테스트 출결 데이터가 있음 (6.2 참조)

#### 테스트 단계

| 단계 | 액션 | 예상 결과 |
|------|------|----------|
| 1 | 출결 목록에서 세션 클릭 | 세션 상세 페이지 표시 |
| 2 | 학생 출결 현황 테이블 확인 | 학생별 출결 상태 표시 |
| 3 | 출결 통계 확인 | 출석/지각/결석/공결/미결 카운트 표시 |
| 4 | 특정 학생 상태 변경 드롭다운 선택 | 상태 변경 옵션 표시 |
| 5 | "출석" 선택 | 상태 변경 완료, 페이지 새로고침 |

#### 확인 사항
- [ ] 변경된 상태가 반영됨
- [ ] "수정됨" 배지 표시 (teacher_forced)
- [ ] 통계가 업데이트됨

### 5.3 시나리오 C: 교수 - 학생 강제 출결 변경

#### 테스트 단계

| 단계 | 액션 | 예상 결과 |
|------|------|----------|
| 1 | 세션 상세 페이지 접속 | 학생 목록 표시 |
| 2 | 학생 행에서 상태 변경 드롭다운 클릭 | 옵션: 출석, 지각, 결석, 공결, 미결 |
| 3 | "공결" 선택 | AJAX 요청 전송 |
| 4 | 결과 확인 | 상태 변경 완료, 페이지 새로고침 |

#### DB 확인
```ruby
# Rails console
record = PanoptoViewResult.last
record.attendance_state  # => 3 (공결)
record.teacher_forced_change  # => 1
record.modified_by_user_id  # => Canvas User ID
```

### 5.4 시나리오 D: 학생 - 본인 출결 조회

#### 사전 조건
- Canvas에 학생 계정으로 로그인
- 테스트 코스에 Student 역할로 등록

#### 테스트 단계

| 단계 | 액션 | 예상 결과 |
|------|------|----------|
| 1 | Canvas 코스 → Attendance 메뉴 클릭 | LTI Launch 성공, 본인 출결 현황 표시 |
| 2 | 출결 목록 확인 | 각 세션별 본인의 출결 상태만 표시 |
| 3 | 특정 세션 클릭 | 세션 상세 페이지 - 본인 기록만 표시 |
| 4 | 출결 변경 시도 | 변경 UI 없음 (학생은 조회만 가능) |

#### 확인 사항
- [ ] 교수용 UI(생성/수정/삭제 버튼) 미표시
- [ ] 다른 학생 정보 미표시
- [ ] 본인 통계만 표시

### 5.5 시나리오 E: 기간 기반 자동 판정

#### VOD 자동 판정 테스트

| 조건 | 현재 시간 | 예상 상태 |
|------|----------|----------|
| 출석 기록 없음 + attendance_finish_at 이전 | 마감 전 | pending (미결) |
| 출석 기록 없음 + attendance_finish_at 이후 | 마감 후 | absent (결석) |
| 출석 기록 없음 + tardiness_finish_at 이후 | 지각 마감 후 | absent (결석) |
| 출석 기록 없음 + 지각 허용 + 지각 기간 중 | 마감~지각마감 | late (지각) |

#### 테스트 방법
```ruby
# Rails console
session = AttendanceSession.first
setting = session.vod_setting

# 출석 마감 시간 조정
setting.update!(attendance_finish_at: 1.hour.ago)

# 서비스 호출
status = AttendanceStatsCalculator.resolve_pending_status(session)
puts status  # => "absent"
```

---

## 6. 테스트 데이터 생성

### 6.1 Rails Console 접속
```bash
bin/rails console
```

### 6.2 출결 세션 및 데이터 생성

```ruby
# LtiContext 확인 또는 생성
ctx = LtiContext.first
unless ctx
  platform = LtiPlatform.first
  ctx = LtiContext.create!(
    context_id: 'test-course-001',
    context_type: 'Course',
    context_title: '테스트 강좌',
    platform_iss: platform.iss,
    canvas_url: platform.iss
  )
end

# 출결 세션 생성 (VOD)
session = ctx.attendance_sessions.create!(
  week: 1,
  lesson_id: 1,
  title: '1주차 OT - 강의 소개',
  attendance_type: 'vod',
  content_tag_id: 12345  # Canvas Module Item ID (실제 값으로 변경)
)

# VOD 설정
session.create_vod_setting!(
  session_id: SecureRandom.uuid,
  allow_attendance: true,
  allow_tardiness: true,
  percent_required: 80,
  unlock_at: 1.week.ago,
  attendance_finish_at: 1.day.from_now,
  tardiness_finish_at: 3.days.from_now
)

puts "세션 생성 완료: #{session.full_title}"
```

### 6.3 외부 시스템 데이터 시뮬레이션

```ruby
# Panopto 출결 결과 생성 (외부 시스템이 INSERT하는 것을 시뮬레이션)
session = AttendanceSession.first

# 학생 1: 출석
PanoptoViewResult.create!(
  content_tag_id: session.content_tag_id,
  session_id: session.vod_setting.session_id,
  user_id: SecureRandom.uuid,
  user_name: 'student001',  # Canvas unique_id (login_id)
  attendance_state: 4       # 출석
)

# 학생 2: 지각
PanoptoViewResult.create!(
  content_tag_id: session.content_tag_id,
  session_id: session.vod_setting.session_id,
  user_id: SecureRandom.uuid,
  user_name: 'student002',
  attendance_state: 2       # 지각
)

# 학생 3: 결석
PanoptoViewResult.create!(
  content_tag_id: session.content_tag_id,
  session_id: session.vod_setting.session_id,
  user_id: SecureRandom.uuid,
  user_name: 'student003',
  attendance_state: 1       # 결석
)

# 학생 4: 미결 (pending)
PanoptoViewResult.create!(
  content_tag_id: session.content_tag_id,
  session_id: session.vod_setting.session_id,
  user_id: SecureRandom.uuid,
  user_name: 'student004',
  attendance_state: 0       # 미결
)

puts "테스트 출결 데이터 #{PanoptoViewResult.count}건 생성 완료"
```

### 6.4 LIVE 세션 테스트 데이터

```ruby
# LIVE 세션 생성
live_session = ctx.attendance_sessions.create!(
  week: 2,
  lesson_id: 1,
  title: '2주차 실시간 강의',
  attendance_type: 'live',
  content_tag_id: 12346
)

# LIVE 설정
live_session.create_live_setting!(
  meeting_id: 'zoom-meeting-123',
  allow_attendance: true,
  allow_tardiness: true,
  attendance_threshold: 80,
  tardiness_threshold: 50,
  start_time: 1.day.ago,
  duration: 3600  # 1시간 (초)
)

# Zoom 출결 결과
ZoomViewResult.create!(
  content_tag_id: live_session.content_tag_id,
  meeting_id: live_session.live_setting.meeting_id,
  user_email: 'student001@school.ac.kr',
  attendance_state: 4  # 출석
)

puts "LIVE 세션 및 출결 데이터 생성 완료"
```

### 6.5 데이터 확인

```ruby
# 세션 목록
AttendanceSession.all.each do |s|
  puts "#{s.week}주차 #{s.lesson_id}차시: #{s.title} (#{s.attendance_type})"
end

# VOD 출결 결과
PanoptoViewResult.all.each do |r|
  puts "#{r.user_name}: #{r.attendance_state_text}"
end

# LIVE 출결 결과
ZoomViewResult.all.each do |r|
  puts "#{r.user_email}: #{r.attendance_state_text}"
end
```

---

## 7. 트러블슈팅

### 7.1 LTI Launch 실패

#### 증상: "세션이 만료되었습니다" 오류

**원인**: LTI Claims가 세션에 저장되지 않음

**해결**:
1. Canvas Developer Key가 ON 상태인지 확인
2. Redirect URI가 정확한지 확인
3. 브라우저 쿠키/세션 삭제 후 재시도

#### 증상: "Canvas Platform 정보를 찾을 수 없습니다" 오류

**원인**: LtiPlatform 레코드가 없거나 ISS/Client ID 불일치

**해결**:
```ruby
# Rails console에서 확인
LtiPlatform.all
# ISS와 Client ID가 Canvas 설정과 일치하는지 확인
```

### 7.2 학생 식별 실패

#### 증상: 학생 출결이 표시되지 않음

**원인**: Custom Parameters 미설정

**해결**:
1. Canvas External Tool 설정에서 Custom Fields 확인:
   ```
   canvas_user_login_id=$Canvas.user.loginId
   ```
2. LTI Claims에 값이 들어오는지 확인:
   ```ruby
   # Controller에서 디버깅
   Rails.logger.info "LTI Claims: #{session[:lti_claims].inspect}"
   ```

### 7.3 출결 강제 변경 실패

#### 증상: "세션이 Canvas와 매핑되지 않았습니다" 오류

**원인**: AttendanceSession의 content_tag_id가 nil

**해결**:
1. 세션 편집에서 Canvas Module Item 선택
2. 또는 직접 content_tag_id 설정:
   ```ruby
   session.update!(content_tag_id: 12345)
   ```

#### 증상: "학생 식별자가 없습니다" 오류

**원인**: student_identifier 파라미터 누락

**해결**:
- 브라우저 개발자 도구에서 AJAX 요청 확인
- `student_identifier` 파라미터가 전송되는지 확인

### 7.4 기간 판정 오류

#### 증상: 마감 후에도 "미결"로 표시

**원인**: VodSetting의 allow_attendance가 false

**해결**:
```ruby
session.vod_setting.update!(allow_attendance: true)
```

### 7.5 로그 확인

```bash
# 전체 로그
tail -f log/development.log

# 특정 키워드 필터
tail -f log/development.log | grep -i "attendance"

# SQL 쿼리 확인
tail -f log/development.log | grep -i "SELECT\|INSERT\|UPDATE"
```

---

## 부록: 체크리스트

### 테스트 전 체크리스트
- [ ] 데이터베이스 마이그레이션 완료
- [ ] LTI Platform 등록 완료
- [ ] Canvas Developer Key 활성화
- [ ] Canvas External Tool 설치
- [ ] Custom Parameters 설정
- [ ] 서버 정상 실행

### 기능별 테스트 체크리스트

#### 교수 기능
- [ ] 출결 목록 조회
- [ ] 출결 세션 생성 (VOD)
- [ ] 출결 세션 생성 (LIVE)
- [ ] 출결 세션 수정
- [ ] 출결 세션 삭제
- [ ] 학생 출결 조회
- [ ] 출결 강제 변경
- [ ] 학생 상세 조회

#### 학생 기능
- [ ] 본인 출결 목록 조회
- [ ] 본인 출결 상세 조회
- [ ] 교수 기능 접근 불가 확인

#### 자동 판정
- [ ] VOD 출석 마감 전: pending
- [ ] VOD 출석 마감 후: absent
- [ ] VOD 지각 기간: late
- [ ] LIVE 종료 후: absent

---

---

## 8. Canvas 원본 로직 비교 검증

### 8.1 핵심 로직 비교표

| 항목 | Canvas 원본 | LTI Tool | 일치 여부 |
|------|-------------|----------|----------|
| **VOD 학생 식별자** | `SisPseudonym.unique_id` | `custom_canvas_user_login_id` | ✅ |
| **LIVE 학생 식별자** | `user.email` | `email` claim | ✅ |
| **우선순위 정렬** | `teacher_forced_change DESC, created_at DESC` | 동일 | ✅ |
| **VOD pending → absent** | `attendance_finish_at` 이후 | 동일 | ✅ |
| **VOD pending → late** | `attendance_finish_at` 후 ~ `tardiness_finish_at` 전 | 동일 | ✅ |
| **LIVE pending → absent** | `start_time + duration` 이후 | 동일 | ✅ |
| **통계 계산** | 기록 없는 학생도 포함 | 동일 | ✅ |

### 8.2 resolve_pending_status 로직 검증

#### VOD (Panopto) 판정 흐름
```
현재시간 < attendance_finish_at?
  → pending (아직 진행 중)

현재시간 >= attendance_finish_at?
  allow_tardiness = true & tardiness_finish_at 존재?
    → 현재시간 < tardiness_finish_at? → late (지각)
    → 현재시간 >= tardiness_finish_at? → absent (결석)
  allow_tardiness = false?
    → absent (결석)
```

#### 테스트 코드
```ruby
# Rails Console에서 실행
session = AttendanceSession.first
setting = session.vod_setting

# 케이스 1: 출석 마감 전
setting.update!(attendance_finish_at: 1.day.from_now)
result = AttendanceStatsCalculator.resolve_pending_status(session)
puts "마감 전: #{result}"  # 기대: "pending"

# 케이스 2: 출석 마감 후, 지각 마감 전
setting.update!(
  attendance_finish_at: 1.hour.ago,
  tardiness_finish_at: 1.day.from_now,
  allow_tardiness: true
)
result = AttendanceStatsCalculator.resolve_pending_status(session)
puts "지각 기간: #{result}"  # 기대: "late"

# 케이스 3: 지각 마감 후
setting.update!(
  attendance_finish_at: 2.days.ago,
  tardiness_finish_at: 1.day.ago
)
result = AttendanceStatsCalculator.resolve_pending_status(session)
puts "지각 마감 후: #{result}"  # 기대: "absent"
```

#### LIVE (Zoom) 판정 흐름
```
현재시간 < (start_time + duration)?
  → pending (라이브 진행 중)

현재시간 >= (start_time + duration)?
  → absent (결석)

주의: Zoom은 지각 개념 없음, 종료 후 바로 결석 판정
```

#### 테스트 코드
```ruby
live_session = AttendanceSession.find_by(attendance_type: 'live')
setting = live_session.live_setting

# 케이스 1: 수업 진행 중
setting.update!(start_time: 30.minutes.ago, duration: 3600)
result = AttendanceStatsCalculator.resolve_pending_status(live_session)
puts "수업 중: #{result}"  # 기대: "pending"

# 케이스 2: 수업 종료 후
setting.update!(start_time: 2.hours.ago, duration: 3600)
result = AttendanceStatsCalculator.resolve_pending_status(live_session)
puts "종료 후: #{result}"  # 기대: "absent"
```

### 8.3 우선순위 처리 검증

Canvas 원본과 동일하게 `teacher_forced_change = 1`인 레코드가 최우선:

```ruby
content_tag_id = 12345
user_name = "student001"

# 1. 자동 판정 레코드 (먼저 생성)
PanoptoViewResult.create!(
  content_tag_id: content_tag_id,
  session_id: "test-session",
  user_id: SecureRandom.uuid,
  user_name: user_name,
  attendance_state: 1,  # absent
  teacher_forced_change: 0
)

# 2. 교수 강제 변경 레코드 (나중에 생성)
PanoptoViewResult.create!(
  content_tag_id: content_tag_id,
  session_id: "test-session",
  user_id: SecureRandom.uuid,
  user_name: user_name,
  attendance_state: 4,  # present
  teacher_forced_change: 1
)

# 조회 - 강제 변경이 우선
record = PanoptoViewResult.latest_for_student(content_tag_id, user_name)
puts "상태: #{record.attendance_state}"  # 기대: 4 (present)
puts "강제 변경: #{record.teacher_forced_change}"  # 기대: 1
```

### 8.4 학생 식별자 매칭 검증

```ruby
# LTI Launch 후 세션 데이터 확인
claims = session[:lti_claims]

puts "=== VOD 식별자 (Panopto) ==="
puts "custom_canvas_user_login_id: #{claims[:custom_canvas_user_login_id]}"
puts "login_id: #{claims[:login_id]}"
puts "user_name: #{claims[:user_name]}"

puts "=== LIVE 식별자 (Zoom) ==="
puts "email: #{claims[:email]}"
puts "user_email: #{claims[:user_email]}"

# DB 레코드와 비교
vod_id = claims[:custom_canvas_user_login_id] || claims[:user_name]
PanoptoViewResult.where(user_name: vod_id).count

live_id = claims[:email]
ZoomViewResult.where(user_email: live_id).count
```

---

## 9. 수정된 코드 변경사항 (2026-03-09)

### 9.1 LTI Claims 추출 개선
**파일**: `app/controllers/lti/launch_controller.rb`

Custom Fields에서 `canvas_user_login_id`를 명시적으로 추출:
```ruby
# Before
custom_params: custom_params

# After
custom_params: custom_params,
custom_canvas_user_login_id: custom_params["canvas_user_login_id"],
custom_canvas_user_id: custom_params["canvas_user_id"]
```

### 9.2 HashWithIndifferentAccess 적용
**파일**: `app/controllers/lti/launch_controller.rb`, `app/controllers/attendance_controller.rb`

Symbol/String 키 모두 접근 가능하도록:
```ruby
session[:lti_claims] = @lti_claims.with_indifferent_access
```

### 9.3 학생 식별자 폴백 추가
**파일**: `app/services/attendance_query_helper.rb`

폴백 옵션 추가:
```ruby
# VOD
lti_claims[:custom_canvas_user_login_id] ||
  lti_claims[:login_id] ||
  lti_claims[:user_name]

# LIVE
lti_claims[:email] ||
  lti_claims[:user_email]
```

---

*이 문서는 Attendance 기능 아키텍처 재설계 (2026-02-27) 이후 작성되었습니다.*
*최종 수정: 2026-03-09 - Canvas 원본 로직 비교 검증 추가*
