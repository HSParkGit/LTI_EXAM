# Canvas Developer Key 설정 - 사용자 정보 전달

## 문제: 사용자 정보가 N/A로 표시됨

이름, 이메일 등이 `N/A`로 나오는 경우, Canvas Developer Key의 **Privacy Level** 설정을 확인해야 합니다.

---

## 🔧 Canvas Developer Key 설정 방법

### 1. Canvas Admin → Developer Keys 접근
1. Canvas Admin 페이지 접속
2. **Developer Keys** 메뉴 클릭
3. 해당 LTI Key 선택 (또는 새로 생성)

### 2. Privacy Level 설정 (중요!)

**Privacy Level**은 사용자 정보를 LTI Tool에 전달할지 여부를 결정합니다.

#### 옵션 1: Public (모든 정보 전달) ⭐ 권장
- **설정**: Privacy Level = `Public`
- **전달되는 정보**:
  - ✅ 사용자 이름 (name, given_name, family_name)
  - ✅ 이메일 (email)
  - ✅ 프로필 사진 (picture)
  - ✅ Canvas User ID
- **용도**: 개발 및 테스트, 신뢰할 수 있는 Tool

#### 옵션 2: Anonymous (최소 정보만)
- **설정**: Privacy Level = `Anonymous`
- **전달되는 정보**:
  - ✅ User Sub (고유 ID만)
  - ❌ 이름, 이메일 등 개인정보 없음
- **용도**: 프라이버시가 중요한 경우

#### 옵션 3: Name Only (이름만)
- **설정**: Privacy Level = `Name Only`
- **전달되는 정보**:
  - ✅ 사용자 이름
  - ❌ 이메일 없음
- **용도**: 이름은 필요하지만 이메일은 불필요한 경우

---

## 📋 Canvas Developer Key 설정 체크리스트

### 필수 설정
- [ ] **Privacy Level**: `Public` (또는 `Name Only`)
- [ ] **Redirect URIs**: `https://your-tool.com/lti/launch`
- [ ] **Initiation Login URL**: `https://your-tool.com/lti/login`
- [ ] **Target Link URI**: `https://your-tool.com/lti/launch`

### 선택 설정 (추가 정보 전달)
- [ ] **Scopes**: 필요한 권한 선택
  - `https://purl.imsglobal.org/spec/lti-ags/scope/score` (점수 업로드)
  - `https://purl.imsglobal.org/spec/lti-ags/scope/lineitem` (과제 정보)
  - `https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly` (사용자 목록)

### Custom Fields (선택적)
Canvas Developer Key에서 **Custom Fields**를 설정하면 추가 정보를 전달할 수 있습니다:

```
canvas_course_id=$Canvas.course.id
canvas_user_id=$Canvas.user.id
canvas_account_id=$Canvas.account.id
```

이미 LTI Launch에서 자동으로 전달되지만, 명시적으로 설정할 수도 있습니다.

---

## 🔍 실제 JWT Payload 확인 방법

현재 코드에 디버깅 로그가 추가되어 있습니다. Rails 로그에서 확인:

```bash
tail -f log/development.log | grep "JWT Payload"
```

또는 브라우저 콘솔에서 확인:
- Launch 화면 하단의 "자세히 보기" 섹션에서 모든 정보 확인

---

## ✅ 설정 후 확인 사항

Privacy Level을 `Public`으로 변경한 후:

1. **Canvas에서 Tool 다시 실행**
   - 기존 세션을 종료하고 다시 Launch
   - JWT는 Launch 시점에 생성되므로 설정 변경 후 재실행 필요

2. **확인할 정보**:
   - ✅ 이름이 표시되는지
   - ✅ 이메일이 표시되는지 (Privacy Level = Public인 경우)
   - ✅ User Sub가 여전히 표시되는지

---

## 🚨 주의사항

### Privacy Level 변경 시
- **기존 Launch 세션**: 변경 전에 생성된 JWT는 이전 설정을 따름
- **새 Launch**: 설정 변경 후 새로 실행해야 새 설정이 적용됨

### 프로덕션 환경
- Privacy Level = `Public`은 모든 사용자 정보를 전달하므로:
  - GDPR, 개인정보보호법 준수 필요
  - Tool이 신뢰할 수 있는지 확인
  - 사용자에게 정보 전달 동의 받기

---

## 📚 참고 자료

- [Canvas LTI Developer Key Documentation](https://canvas.instructure.com/doc/api/file.lti_dev_key_config.html)
- [Canvas Privacy Level Settings](https://community.canvaslms.com/t5/Canvas-Developers-Group/Privacy-Levels-in-LTI-1-3/ba-p/300000)

---

## 💡 빠른 해결 방법

1. Canvas Admin → Developer Keys
2. 해당 LTI Key 선택
3. **Privacy Level** = `Public`으로 변경
4. 저장
5. Canvas에서 Tool 다시 실행

이렇게 하면 이름, 이메일 등이 정상적으로 표시됩니다.

