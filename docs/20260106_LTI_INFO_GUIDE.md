# LTI 1.3에서 사용 가능한 정보 가이드

## 📋 LTI Launch에서 받을 수 있는 정보 (현재 구현됨)

LTI 1.3 Launch에서 **한 번의 Launch 요청**으로 받을 수 있는 정보입니다.

### 1. 사용자 정보
- ✅ `user_sub`: Canvas 사용자 고유 ID (항상 제공)
- ✅ `user_name`: 전체 이름
- ✅ `user_given_name`: 이름
- ✅ `user_family_name`: 성
- ⚠️ `user_email`: 이메일 (Canvas Developer Key 설정에 따라 제공될 수도, 안될 수도 있음)
- ⚠️ `user_picture`: 프로필 사진 URL (선택적)
- ✅ `canvas_user_id`: Canvas 내부 사용자 ID

### 2. 코스(Context) 정보
- ✅ `course_id`: 코스 ID (LTI 컨텍스트 ID)
- ✅ `context_title`: 코스 제목
- ✅ `context_type`: 코스 타입 (Course, Group 등)
- ✅ `canvas_course_id`: Canvas 내부 코스 ID (Canvas API 호출 시 필요)

### 3. Resource Link 정보 (과제/모듈에서 실행된 경우만)
- ✅ `resource_link_id`: 과제/모듈 ID
- ✅ `resource_link_title`: 과제/모듈 제목
- ✅ `resource_link_description`: 설명

### 4. 역할 정보
- ✅ `user_role`: 간소화된 역할 (:instructor 또는 :student)
- ✅ `user_roles`: 전체 역할 배열

### 5. LTI 메타데이터
- ✅ `deployment_id`: LTI 배포 ID
- ✅ `issuer`: Canvas 인스턴스 URL
- ✅ `audience`: Client ID

---

## ❌ Canvas API로 가져와야 하는 정보

다음 정보들은 **Canvas REST API**를 호출해야 가져올 수 있습니다.

### 1. 학생 목록
```
GET /api/v1/courses/:course_id/users?enrollment_type[]=student
```

### 2. 과제 목록
```
GET /api/v1/courses/:course_id/assignments
```

### 3. 과제 상세 정보
```
GET /api/v1/courses/:course_id/assignments/:assignment_id
```

### 4. 학생 제출물
```
GET /api/v1/courses/:course_id/assignments/:assignment_id/submissions
```

### 5. 성적 정보
```
GET /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id
POST /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id (점수 업로드)
```

### 6. 코스 상세 정보
```
GET /api/v1/courses/:course_id
```

### 7. 모듈 정보
```
GET /api/v1/courses/:course_id/modules
```

### 8. 코스 파일
```
GET /api/v1/courses/:course_id/files
```

### 9. 사용자 프로필
```
GET /api/v1/users/:user_id/profile
```

---

## 🔑 Canvas API 인증 방법

Canvas API를 호출하려면 **Access Token**이 필요합니다.

### 방법 1: LTI Advantage Access Token (권장)

LTI 1.3 Launch 시 받은 정보를 사용하여 Access Token을 발급받습니다:

```
POST {canvas_url}/login/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
client_assertion={JWT_TOKEN}
scope=https://purl.imsglobal.org/spec/lti-ags/scope/score https://purl.imsglobal.org/spec/lti-ags/scope/lineitem
```

하지만 이는 LTI Advantage (AGS, NRPS 등) 확장 기능이 필요합니다.

### 방법 2: Canvas Developer Key Access Token (간단)

Canvas Developer Key에서 직접 Access Token을 생성:

1. Canvas Admin → Developer Keys → 해당 Key 선택
2. "Access Token" 또는 "API Token" 생성
3. HTTP Header에 포함:
   ```
   Authorization: Bearer {access_token}
   ```

### 방법 3: User Access Token

Canvas 사용자 계정으로 Access Token 생성 (Canvas 설정에서).

---

## 📦 LTI Advantage 확장 (향후 구현 가능)

LTI 1.3의 확장 기능들을 사용하면 API 없이도 일부 정보를 받을 수 있습니다:

### 1. AGS (Assignment and Grade Services)
- 과제 점수 업로드
- 점수 조회
- Line Item 관리

### 2. NRPS (Names and Role Provisioning Services)
- 코스의 사용자 목록 조회
- 역할 정보 조회

### 3. Deep Linking
- 콘텐츠 선택 및 코스에 추가

---

## 🎯 현재 프로젝트 상태

✅ **구현 완료**:
- LTI 1.3 Core Launch
- 사용자 정보 추출
- 코스 정보 추출
- 역할 정보 추출

❌ **미구현** (Canvas API 필요):
- 학생 목록 조회
- 과제 목록/상세 조회
- 제출물 조회
- 성적 업로드/조회
- 코스 상세 정보

---

## 💡 권장 사항

1. **현재 Launch 정보로 할 수 있는 것**:
   - 사용자 인증
   - 코스 컨텍스트 확인
   - 역할 기반 기능 분기

2. **Canvas API가 필요한 경우**:
   - 학생 목록이 필요할 때
   - 과제 정보를 조회해야 할 때
   - 성적을 업로드해야 할 때

3. **Access Token 관리**:
   - Developer Key Access Token 사용 (가장 간단)
   - 또는 LTI Advantage Access Token (더 안전하지만 구현 복잡)

---

## 📚 참고 자료

- [Canvas API Documentation](https://canvas.instructure.com/doc/api/)
- [LTI 1.3 Core Specification](https://www.imsglobal.org/spec/lti/v1p3/)
- [LTI Advantage](https://www.imsglobal.org/activity/learning-tools-interoperability)

