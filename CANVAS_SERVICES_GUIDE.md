# Canvas Developer Key Services 설정 가이드

## 현재 상태 (MVP 단계)

**현재 프로젝트는 LTI 1.3 Core만 구현되어 있습니다.**
- ✅ Services를 **아무것도 체크하지 않아도** 기본 Launch는 정상 작동합니다.
- ✅ 사용자 정보, 코스 정보, 역할 정보는 Services 없이도 받을 수 있습니다.

---

## Services 선택 가이드

### 🎯 현재 MVP에서는 체크 불필요

현재 구현된 기능:
- LTI Launch (사용자 인증)
- 코스 정보 조회
- 역할 정보 조회

이것들은 **Services 없이도** 작동합니다.

---

## 📋 Services 설명 및 추천

### 1. Assignment and Grade Services (AGS) ⭐⭐⭐

**체크 항목:**
- ✅ `Can create and view assignment data in the gradebook associated with the tool.`
- ✅ `Can view assignment data in the gradebook associated with the tool.`
- ✅ `Can view submission data for assignments associated with the tool.`
- ✅ `Can create and update submission results for assignments associated with the tool.`

**용도:**
- 과제 점수 업로드 (Canvas Gradebook에 반영)
- 과제 점수 조회
- 제출물 조회

**언제 필요:**
- Tool에서 생성한 과제의 점수를 Canvas에 업로드할 때
- Canvas Gradebook과 연동할 때

**구현 필요:**
- AGS (Assignment and Grade Services) 엔드포인트 구현
- Canvas API 대신 AGS를 사용하여 점수 업로드

---

### 2. Names and Role Provisioning Services (NRPS) ⭐⭐

**체크 항목:**
- ✅ `Can retrieve user data associated with the context the tool is installed in.`

**용도:**
- 코스의 학생 목록 조회
- 역할 정보 조회
- Canvas API 없이 사용자 목록 가져오기

**언제 필요:**
- Tool에서 코스의 학생 목록이 필요할 때
- Canvas API 호출 없이 사용자 정보를 가져올 때

**구현 필요:**
- NRPS 엔드포인트 구현
- Canvas API 대신 NRPS를 사용하여 사용자 목록 조회

---

### 3. Deep Linking ⭐

**체크 항목:**
- ✅ `Can view the content of a page the tool is launched from.`

**용도:**
- Tool에서 콘텐츠를 선택하여 Canvas 코스에 추가
- Tool 콘텐츠를 Canvas 모듈/과제로 직접 추가

**언제 필요:**
- Tool에서 생성한 콘텐츠를 Canvas에 추가해야 할 때
- 학생이 Tool에서 콘텐츠를 선택하여 제출할 때

**구현 필요:**
- Deep Linking 엔드포인트 구현
- 콘텐츠 선택 UI 구현

---

### 4. 기타 Services (현재 불필요)

#### Platform Notification Service
- Tool에 이벤트 알림을 보내는 서비스
- 복잡한 구현 필요
- **현재는 불필요**

#### Asset Service / Asset Report Service
- Canvas 자산을 가져오는 서비스
- **현재는 불필요**

#### EULA Service
- Tool의 이용약관 관리
- **현재는 불필요**

#### Public JWK Update
- Tool의 공개키 업데이트
- **현재는 불필요**

#### Account Lookup
- 계정 정보 조회
- Canvas API로 대체 가능
- **현재는 불필요**

#### Progress Service
- 진행 상황 조회
- **현재는 불필요**

---

## 💡 추천 설정 (현재 MVP 단계)

### 옵션 1: 아무것도 체크하지 않음 (권장 - 현재)

**이유:**
- 현재 구현된 기능만 사용
- Services 구현 없이도 정상 작동
- 나중에 필요할 때 추가 가능

**체크 항목:** 없음

---

### 옵션 2: 향후 사용을 위한 준비

나중에 점수 업로드나 학생 목록이 필요할 것을 대비:

**체크 항목:**
- ✅ `Can create and view assignment data in the gradebook associated with the tool.`
- ✅ `Can view submission data for assignments associated with the tool.`
- ✅ `Can create and update submission results for assignments associated with the tool.`
- ✅ `Can retrieve user data associated with the context the tool is installed in.`

**주의:**
- 이 항목들을 체크해도 **현재는 작동하지 않습니다**
- Tool에서 해당 Services를 구현해야 사용 가능
- 체크만 해두면 나중에 구현할 때 바로 사용 가능

---

## 🎯 결론 및 권장사항

### 현재 MVP 단계
**→ 아무것도 체크하지 않음 (권장)**

이유:
1. 현재 구현된 기능만 사용
2. Services 없이도 Launch는 정상 작동
3. 불필요한 설정으로 인한 혼란 방지

### 향후 확장 계획이 있다면
**→ AGS + NRPS 체크 (구현은 나중에)**

체크 항목:
- Assignment and Grade Services 관련 4개
- `Can retrieve user data` (NRPS)

---

## 📚 참고

- Services를 체크해도 Tool에서 구현하지 않으면 사용할 수 없습니다
- Services는 **선택적 기능**입니다
- LTI 1.3 Core만으로도 기본 기능은 모두 사용 가능합니다

---

## ✅ 최종 추천

**현재는 아무것도 체크하지 마세요.**

나중에 다음 기능이 필요하면 그때 체크:
- 점수 업로드 → AGS
- 학생 목록 → NRPS
- 콘텐츠 추가 → Deep Linking

