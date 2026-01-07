# LTI Tool 문서 모음

이 디렉토리는 LTI 1.3 Tool Provider 프로젝트의 모든 설계 및 문서를 포함합니다.

## 📚 문서 목록

### 🎯 설계 문서

1. **MVP_범위_및_의사결정.md**
   - MVP 기능 범위 정의
   - 최종 의사결정 사항
   - 구현 체크리스트

2. **PROJECT_이식_계획.md**
   - Canvas 프로젝트의 Project 기능을 LTI Tool로 이식하는 단계별 계획
   - 데이터베이스, 모델, 서비스, 컨트롤러 설계

3. **추가_설계_필요사항.md**
   - MVP 이후 추가 설계 사항
   - Canvas API 인증, 세션 관리, 에러 처리 등

4. **ERB_UI_구현_설계.md** ⭐ **새로 추가**
   - 원본 Canvas React 컴포넌트를 참고한 ERB UI 구현 설계
   - 프로젝트 목록, 생성, 상세 뷰 설계
   - Submission 통계, STEP 표시 등 기능 설계

### 🔧 기술 문서

5. **Canvas_API_인증_설계.md**
   - Canvas API 인증 방식 (Personal Access Token)
   - OAuth 2.0 Client Credentials Grant (참고용)

6. **Canvas_SERVICES_GUIDE.md**
   - Canvas API 서비스 가이드
   - AGS, NRPS, Deep Linking 등

7. **LTI_INFO_GUIDE.md**
   - LTI 1.3에서 사용 가능한 정보 가이드
   - LTI Claims 설명

### ⚙️ 설정 문서

8. **CANVAS_DEVELOPER_KEY_SETTINGS.md**
   - Canvas Developer Key 설정 방법
   - Custom Fields 설정

9. **CANVAS_SETUP.md**
   - Canvas 설정 가이드

### 📝 기타

10. **IMPLEMENTATION_SUMMARY.md**
    - 구현 요약
    - 주요 변경 사항

11. **README.md** (이 파일)
    - 문서 목록 및 설명

---

## 🚀 빠른 시작

### 개발 시작 전 필독
1. `MVP_범위_및_의사결정.md` - MVP 범위 확인
2. `PROJECT_이식_계획.md` - 전체 구조 이해

### UI 구현 시 참고
1. `ERB_UI_구현_설계.md` - ERB 템플릿 설계
2. 원본 Canvas React 컴포넌트 (`canvas/ui/features/hy_projects/`)

### Canvas API 연동 시 참고
1. `Canvas_API_인증_설계.md` - 인증 방식
2. `Canvas_SERVICES_GUIDE.md` - API 서비스 가이드

---

## 📂 원본 Canvas 프로젝트 참고

원본 Canvas 프로젝트의 React 컴포넌트는 다음 경로에 있습니다:
- `canvas/ui/features/hy_projects/` - 프로젝트 목록
- `canvas/ui/features/hy_project_new_v2/` - 프로젝트 생성
- `canvas/ui/features/hy_project_show/` - 프로젝트 상세

---

**마지막 업데이트**: 2026-01-06
