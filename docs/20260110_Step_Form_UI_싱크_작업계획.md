# LTI Step Form과 Canvas Assignment Form UI 싱크 작업 계획

**작성일**: 2026-01-10
**목적**: LTI 프로젝트의 Step 생성/수정 페이지를 Canvas Assignment 생성/수정 페이지와 정확히 일치시키기
**작업 방식**: 단계별 진행, 각 단계마다 MD 파일에 흔적 남기기

---

## 📋 현재 상황 분석

### Canvas Assignment Form 구조 (이미지 분석)

**레이아웃**:
- 헤더: "Step 1" 제목
- 폼 필드들:
  1. **Assignment Name** (텍스트 입력)
  2. **Description** (Rich Text Editor - TinyMCE)
  3. **Points** (숫자 입력, 기본값: 0)
  4. **Display Grade as** (드롭다운: 배점/완료/점수 등)
  5. **Submission Type** (드롭다운: Online/No Submission 등)
     - Online 선택 시:
       - Website URL (체크박스)
       - File Uploads (체크박스)
       - Restrict Upload File Types (체크박스, File Uploads 체크 시 표시)
  6. **Submission Attempts** (드롭다운: Unlimited/Limited)
  7. **Peer Reviews** (체크박스: Require Peer Reviews)
  8. **Assign** (날짜/시간 입력 필드 3개)
     - Due Date (마감일)
     - Available from (시작일)
     - Until (종료일)

**특징**:
- Rich Text Editor는 한국어 UI (편집, 보기, 삽입, 형식, 도구, 테이블 메뉴)
- 각 필드는 왼쪽 라벨, 오른쪽 입력 필드 형태
- Submission Type에 따라 하위 옵션이 동적으로 표시됨

### LTI Step Form 현재 구조

**레이아웃**:
- 헤더: "Step 1" 제목 ✅
- 폼 필드들:
  1. **Assignment Name** (텍스트 입력) ✅
  2. **Description** (텍스트 영역 - plain textarea) ⚠️ Rich Text Editor 아님
  3. **Points** (숫자 입력) ✅
  4. **Display Grade as** ❌ 없음
  5. **Submission Type** ❌ 없음
  6. **Submission Attempts** ❌ 없음
  7. **Peer Reviews** ❌ 없음
  8. **Assign** (날짜/시간 입력 필드 3개) ✅
     - Due Date ✅
     - Available from ✅
     - Until ✅

**추가 기능**:
- **Create Slack Channel** 섹션 ⚠️ 숨김 처리 필요

---

## 🎯 목표 및 제약사항

### 목표
1. Canvas Assignment Form과 **시각적으로 동일**하게 만들기
2. 모든 UI 요소 정확히 일치시키기
3. Slack 기능 숨김 처리 (LTI 프로젝트에서 사용 안 함)

### 제약사항
1. **Rich Text Editor**: TinyMCE 또는 유사한 라이브러리 필요
2. **동적 UI**: Submission Type 선택에 따른 하위 옵션 표시
3. **Slack 기능**: 완전히 제거하지 않고 숨김 처리 (나중에 필요 시 복원 가능)

---

## 🔍 Canvas vs LTI 비교 분석

| 항목 | Canvas | LTI | 상태 |
|------|--------|-----|------|
| Assignment Name | ✅ | ✅ | ✅ 일치 |
| Description (Rich Text Editor) | ✅ | ⚠️ (plain textarea) | ❌ 불일치 |
| Points | ✅ | ✅ | ✅ 일치 |
| Display Grade as | ✅ | ❌ | ❌ 없음 |
| Submission Type | ✅ (Online/No Submission) | ❌ | ❌ 없음 |
| Submission Type - Online Options | ✅ (Website URL, File Uploads) | ❌ | ❌ 없음 |
| Submission Attempts | ✅ (Unlimited/Limited) | ❌ | ❌ 없음 |
| Peer Reviews | ✅ (체크박스) | ❌ | ❌ 없음 |
| Assign (Due Date, Available from, Until) | ✅ | ✅ | ✅ 일치 |
| Slack Channel Creation | ❌ (Canvas에 없음) | ⚠️ (있음) | ⚠️ 숨김 처리 필요 |

---

## 📝 단계별 작업 계획

### Phase 1: 현재 상태 정확히 파악 ✅

**작업 내용**:
- [x] Canvas Assignment Form 이미지 분석
- [x] LTI Step Form 현재 코드 확인 (`new.html.erb`, `edit.html.erb`)
- [x] 데이터 구조 확인 (Project, Assignment 필드)
- [x] Canvas API Assignment 필드 확인

**결과**:
- Canvas: Points, Display Grade as, Submission Type, Submission Attempts, Peer Reviews 필드 존재
- LTI: Points, Assign 필드만 존재
- LTI에 Create Slack Channel 섹션 있음 (숨김 처리 필요)

---

### Phase 2: 구현 난이도 평가

#### 2.1 필드 추가 난이도

**쉬운 항목** (단순 필드 추가):
- ✅ **Display Grade as** (드롭다운)
  - 난이도: ⭐⭐ (쉬움)
  - Canvas API 필드: `grading_type` (points, pass_fail, percent, letter_grade 등)
  - 구현: 단순 select 태그 추가

- ✅ **Points** (이미 존재)
  - 난이도: ✅ 완료

- ✅ **Submission Attempts** (드롭다운)
  - 난이도: ⭐⭐ (쉬움)
  - Canvas API 필드: `allowed_attempts` (null = unlimited, 숫자 = limited)
  - 구현: select 태그 (Unlimited/Limited 선택)

- ✅ **Peer Reviews** (체크박스)
  - 난이도: ⭐⭐ (쉬움)
  - Canvas API 필드: `peer_reviews` (boolean)
  - 구현: 단순 체크박스 추가

**중간 난이도** (동적 UI 필요):
- ⚠️ **Submission Type** (드롭다운 + 동적 옵션)
  - 난이도: ⭐⭐⭐ (보통)
  - Canvas API 필드: `submission_types` (array: online_url, online_upload, online_text_entry 등)
  - 구현:
    - 드롭다운 선택 (Online/No Submission)
    - Online 선택 시 하위 옵션 표시:
      - Website URL (체크박스)
      - File Uploads (체크박스)
      - Restrict Upload File Types (체크박스, File Uploads 체크 시 표시)
  - JavaScript로 동적 표시/숨김 처리 필요

**어려운 항목** (외부 라이브러리 필요):
- ⚠️ **Description (Rich Text Editor)**
  - 난이도: ⭐⭐⭐⭐ (어려움)
  - Canvas는 TinyMCE 사용 (한국어 UI)
  - 구현 옵션:
    - 옵션 1: TinyMCE 통합 (Canvas와 동일)
    - 옵션 2: 다른 Rich Text Editor (Trix, Quill 등)
    - 옵션 3: 일단 textarea 유지 (나중에 추가)
  - **권장**: 옵션 1 (TinyMCE) - Canvas와 동일한 UX

#### 2.2 전체 구현 난이도

**예상 작업 시간**:
- Display Grade as: 30분
- Submission Type (드롭다운 + 동적 옵션): 1-2시간
- Submission Attempts: 30분
- Peer Reviews: 30분
- Rich Text Editor (TinyMCE): 2-3시간 (초기 설정 포함)
- Slack 섹션 숨김: 10분

**총 예상 시간**: 4-6시간 (Rich Text Editor 포함)

**난이도 종합 평가**: ⭐⭐⭐ (보통)
- 대부분의 필드는 단순 추가
- Submission Type 동적 UI가 약간 복잡
- Rich Text Editor 통합이 가장 복잡하지만, 라이브러리 사용으로 어렵지 않음

---

### Phase 3: 구현 작업

#### 3.1 Slack 섹션 숨김 처리

**작업 내용**:
- `new.html.erb`, `edit.html.erb`에서 "Create Slack Channel" 섹션 제거 또는 숨김
- CSS로 `display: none` 처리 (나중에 복원 가능하도록)

**구현 위치**:
- `app/views/projects/new.html.erb` (라인 73-86)
- `app/views/projects/edit.html.erb` (라인 74-87)

#### 3.2 Display Grade as 필드 추가

**Canvas API 필드**: `grading_type`
- 값: `points` (배점), `pass_fail` (완료), `percent` (백분율), `letter_grade` (등급) 등

**구현**:
- Step Form에 드롭다운 추가
- 기본값: `points` (배점)
- 위치: Points 필드 아래

#### 3.3 Submission Type 필드 추가

**Canvas API 필드**: `submission_types` (array)
- `online_url`: Website URL
- `online_upload`: File Uploads
- `online_text_entry`: Text Entry
- `none`: No Submission

**구현**:
1. 드롭다운 추가 (Online/No Submission)
2. Online 선택 시 하위 옵션 표시:
   - Website URL (체크박스)
   - File Uploads (체크박스)
   - Restrict Upload File Types (체크박스, File Uploads 체크 시에만 표시)
3. JavaScript로 동적 표시/숨김 처리

**데이터 구조**:
- `submission_types`: 배열로 저장
  - `["online_upload"]`: File Uploads만
  - `["online_url"]`: Website URL만
  - `["online_upload", "online_url"]`: 둘 다

#### 3.4 Submission Attempts 필드 추가

**Canvas API 필드**: `allowed_attempts`
- `null`: Unlimited
- 숫자: Limited (예: 3)

**구현**:
- 드롭다운 추가 (Unlimited/Limited)
- Limited 선택 시 숫자 입력 필드 표시
- 기본값: Unlimited

#### 3.5 Peer Reviews 필드 추가

**Canvas API 필드**: `peer_reviews` (boolean)

**구현**:
- 체크박스 추가 ("Require Peer Reviews")
- 기본값: false (체크 해제)

#### 3.6 Rich Text Editor 통합 (선택 사항)

**옵션 1: TinyMCE 통합** (권장)
- Canvas와 동일한 UX
- 한국어 UI 지원
- Gem: `tinymce-rails`
- 초기 설정: 2-3시간

**옵션 2: 나중에 추가**
- 일단 textarea 유지
- 나중에 Rich Text Editor 추가

**권장**: 옵션 1 (TinyMCE) - Canvas와 일치시키기 위해

---

## 🔧 구현 세부 사항

### Step 1: Slack 섹션 숨김 처리

**파일**: `app/views/projects/new.html.erb`, `app/views/projects/edit.html.erb`

**방법 1: 완전 제거** (권장 - 나중에 필요 없음)
- 라인 73-86 제거

**방법 2: CSS로 숨김** (나중에 복원 가능)
- CSS 클래스 추가: `style="display: none;"`

**결정**: 방법 1 (완전 제거) - 사용자 요청대로

### Step 2: 필드 추가 순서

1. **Display Grade as** (가장 쉬움)
2. **Submission Attempts** (쉬움)
3. **Peer Reviews** (쉬움)
4. **Submission Type** (동적 UI 필요)
5. **Rich Text Editor** (가장 복잡, 선택 사항)

### Step 3: JavaScript 동적 UI

**Submission Type 동적 표시 로직**:
```javascript
// Submission Type 변경 시
document.getElementById('submission_type').addEventListener('change', function() {
  const isOnline = this.value === 'online';
  const onlineOptions = document.getElementById('online-options');
  onlineOptions.style.display = isOnline ? 'block' : 'none';
  
  // File Uploads 체크 해제 시 Restrict 옵션 숨김
  if (!isOnline) {
    document.getElementById('restrict-file-types').style.display = 'none';
  }
});

// File Uploads 체크박스 변경 시
document.getElementById('file-uploads').addEventListener('change', function() {
  const restrictOptions = document.getElementById('restrict-file-types');
  restrictOptions.style.display = this.checked ? 'block' : 'none';
});
```

---

## 📊 진행 상황 추적

### 완료된 작업 ✅
- [x] 현재 상태 분석
- [x] Canvas Assignment Form 이미지 분석
- [x] LTI Step Form 현재 코드 확인
- [x] 구현 난이도 평가

### 진행 중인 작업 🔄
- [x] Slack 섹션 제거 ✅
- [x] Display Grade as 필드 추가 ✅
- [x] Submission Type 필드 추가 (동적 UI 포함) ✅
- [x] Submission Attempts 필드 추가 ✅
- [x] Peer Reviews 필드 추가 ✅
- [x] edit.html.erb에도 동일한 필드들 추가 ✅
- [ ] Rich Text Editor 통합 (선택 사항 - 나중에 추가)

### 대기 중인 작업 ⏳
- [ ] 테스트 및 검증
- [ ] Canvas와 시각적 비교

---

## 💡 주요 결정 사항 (사용자 결정 필요)

### 1. Slack 섹션 처리 방법 ⚠️ **결정 필요**

**옵션 A: 완전 제거** (권장)
- ✅ 코드에서 완전히 삭제
- ✅ 유지보수 측면에서 깔끔
- ❌ 나중에 필요 시 다시 추가 필요

**옵션 B: CSS로 숨김** (보류)
- ✅ 나중에 쉽게 복원 가능
- ❌ 코드에 불필요한 부분 남음
- ❌ 유지보수 시 혼란 가능

**현재 권장**: **옵션 A** (완전 제거) - 사용자 요청대로

---

### 2. Rich Text Editor 통합 ⚠️ **결정 필요**

**옵션 A: TinyMCE 통합** (Canvas와 동일)
- ✅ Canvas와 동일한 UX
- ✅ 한국어 UI 지원
- ✅ 사용자 경험 일관성
- ❌ 초기 설정 시간 소요 (2-3시간)
- ❌ Gem 추가 필요 (`tinymce-rails`)

**옵션 B: 다른 Rich Text Editor** (Trix, Quill 등)
- ✅ 더 가볍거나 현대적일 수 있음
- ❌ Canvas와 다른 UX
- ❌ 한국어 UI 설정 필요

**옵션 C: 일단 textarea 유지** (나중에 추가)
- ✅ 빠른 구현 (다른 필드 먼저)
- ✅ 나중에 필요 시 추가 가능
- ❌ Canvas와 다른 UX (일시적)

**현재 권장**: **옵션 A** (TinyMCE) 또는 **옵션 C** (나중에 추가)

---

### 3. Rich Text Editor 적용 시점 ⚠️ **결정 필요**

**옵션 O: 지금 구현** (다른 필드와 함께)
- ✅ 한 번에 완성
- ✅ Canvas와 완전히 일치
- ❌ 작업 시간 증가 (2-3시간 추가)

**옵션 X: 나중에 추가** (기본 필드 먼저)
- ✅ 빠른 MVP 완성
- ✅ 필수 필드 먼저 검증
- ❌ 두 번 작업 (나중에 다시 작업)

**현재 권장**: **옵션 X** (나중에 추가) - MVP 우선

---

### 4. 필드 추가 순서 ✅ **결정됨**

**결정**: 쉬운 것부터 (Display Grade as → Submission Attempts → Peer Reviews → Submission Type → Rich Text Editor)
**이유**:
- 점진적 개발
- 각 단계마다 테스트 가능
- 리스크 최소화

---

## 🚀 다음 단계

1. **Slack 섹션 제거** - 우선순위: 높음
2. **Display Grade as 필드 추가** - 우선순위: 높음
3. **Submission Attempts 필드 추가** - 우선순위: 높음
4. **Peer Reviews 필드 추가** - 우선순위: 높음
5. **Submission Type 필드 추가** - 우선순위: 중간 (동적 UI)
6. **Rich Text Editor 통합** - 우선순위: 낮음 (선택 사항)

---

## 📝 작업 요약

### 구현 난이도 평가 결과

**전체 난이도**: ⭐⭐⭐ (보통)

**쉬운 항목** (30분-1시간):
- Display Grade as
- Submission Attempts
- Peer Reviews
- Slack 섹션 제거

**중간 난이도** (1-2시간):
- Submission Type (동적 UI)

**어려운 항목** (2-3시간):
- Rich Text Editor 통합 (선택 사항)

**결론**: 
- 대부분의 필드는 **단순 추가**로 구현 가능
- Submission Type은 **동적 UI**가 필요하지만 복잡하지 않음
- Rich Text Editor는 **외부 라이브러리 통합**이 필요하지만, Canvas와 동일한 UX를 위해서는 권장

**예상 총 작업 시간**: 4-6시간 (Rich Text Editor 포함)

---

---

## ✅ 사용자 결정 필요 사항

### 결정 1: Slack 섹션 처리 방법
- [O] **옵션 A**: 완전 제거 (권장)
- [ ] **옵션 B**: CSS로 숨김

**선택**: ___________

### 결정 2: Rich Text Editor 통합
- [ ] **옵션 A**: TinyMCE 통합 (Canvas와 동일)
- [ ] **옵션 B**: 다른 Rich Text Editor
- [O] **옵션 C**: 일단 textarea 유지 (나중에 추가)

**선택**: ___________

### 결정 3: Rich Text Editor 적용 시점
- [ ] **옵션 O**: 지금 구현 (다른 필드와 함께)
- [O] **옵션 X**: 나중에 추가 (기본 필드 먼저)

**선택**: ___________

---

---

## ✅ 완료된 작업 (2026-01-10)

### 1. Slack 섹션 제거 ✅
- **파일**: `app/views/projects/new.html.erb`, `app/views/projects/edit.html.erb`
- **변경**: "Create Slack Channel" 섹션 완전 제거
- **결정**: 옵션 A (완전 제거)

### 2. Display Grade as 필드 추가 ✅
- **위치**: Points 필드 아래
- **구현**: 드롭다운 (배점/완료/백분율/등급)
- **기본값**: 배점 (points)
- **Canvas API 필드**: `grading_type`

### 3. Submission Type 필드 추가 ✅
- **위치**: Display Grade as 아래
- **구현**: 
  - 드롭다운 (Online/No Submission)
  - Online 선택 시 하위 옵션 표시:
    - Website URL (체크박스)
    - File Uploads (체크박스)
    - Restrict Upload File Types (체크박스, File Uploads 체크 시 표시)
- **동적 UI**: JavaScript로 표시/숨김 처리
- **Canvas API 필드**: `submission_types` (array)

### 4. Submission Attempts 필드 추가 ✅
- **위치**: Submission Type 아래
- **구현**: 
  - 드롭다운 (Unlimited/Limited)
  - Limited 선택 시 숫자 입력 필드 표시
- **동적 UI**: JavaScript로 숫자 입력 필드 표시/숨김
- **기본값**: Unlimited
- **Canvas API 필드**: `allowed_attempts` (null = unlimited, 숫자 = limited)

### 5. Peer Reviews 필드 추가 ✅
- **위치**: Submission Attempts 아래
- **구현**: 체크박스 ("Require Peer Reviews")
- **기본값**: false (체크 해제)
- **Canvas API 필드**: `peer_reviews` (boolean)

### 6. edit.html.erb에도 동일한 필드들 추가 ✅
- **파일**: `app/views/projects/edit.html.erb`
- **변경**: new.html.erb와 동일한 필드들 추가
- **특징**: 기존 Assignment 데이터 로드 시 값 표시

### 수정 파일 목록
- `app/views/projects/new.html.erb`
- `app/views/projects/edit.html.erb`

### 다음 단계
- [ ] 백엔드에서 submission_types 배열 처리 확인
- [ ] 테스트 및 검증
- [ ] Canvas와 시각적 비교
- [ ] Rich Text Editor 통합 (나중에 추가)

---

**작성자**: Claude AI
**검토자**: 박형언
**최종 수정일**: 2026-01-10
**작업 상태**: Phase 3 기본 구현 완료 ✅ (Rich Text Editor 제외)
