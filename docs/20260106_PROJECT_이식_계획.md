# Project 기능 LTI Tool 이식 계획

## 📋 이식 가능 여부: ✅ 가능

Canvas 프로젝트의 Project 기능을 LTI Tool로 이식할 수 있습니다. 단계별로 진행합니다.

---

## 🔄 이식 단계별 계획

### Step 1: 데이터베이스 마이그레이션 생성

**목표**: Project 테이블과 LTI Context 매핑 테이블 생성

**생성할 파일**:
- `db/migrate/xxx_create_lti_contexts.rb`
- `db/migrate/xxx_create_projects.rb`

**변경 사항**:
- Canvas의 `context_id`, `context_type` → LTI의 `lti_context_id`로 변경
- Canvas Assignment 참조 제거 (Canvas API로 관리)
- `assignment_ids` 배열 필드 추가 (Canvas Assignment ID 저장)

**코드 예시**:
```ruby
# db/migrate/xxx_create_lti_contexts.rb
class CreateLtiContexts < ActiveRecord::Migration[7.1]
  def change
    create_table :lti_contexts do |t|
      t.string :context_id, null: false          # LTI Context ID
      t.string :context_type, null: false        # "Course"
      t.string :context_title                   # 코스 제목
      t.string :platform_iss, null: false       # Canvas Platform ISS
      t.string :canvas_url, null: false         # Canvas 인스턴스 URL
      t.string :deployment_id                   # LTI Deployment ID
      t.timestamps
    end
    add_index :lti_contexts, [:context_id, :platform_iss], unique: true
  end
end

# db/migrate/xxx_create_projects.rb
class CreateProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :projects do |t|
      t.references :lti_context, null: false, foreign_key: true
      t.string :name, null: false
      t.string :lti_user_sub, null: false       # 생성한 사용자의 LTI User Sub
      t.text :assignment_ids, array: true, default: []  # Canvas Assignment ID 배열
      t.timestamps
    end
  end
end
```

---

### Step 2: 모델 생성

**목표**: Project 모델과 LtiContext 모델 생성

**생성할 파일**:
- `app/models/lti_context.rb`
- `app/models/project.rb`

**변경 사항**:
- Canvas 의존성 제거 (`context`, `assignments` 관계 제거)
- LTI Context와 연결
- Canvas Assignment는 ID 배열로만 참조

**코드 예시**:
```ruby
# app/models/lti_context.rb
class LtiContext < ApplicationRecord
  has_many :projects, dependent: :destroy
  belongs_to :lti_platform, foreign_key: :platform_iss, primary_key: :iss
  
  validates :context_id, uniqueness: { scope: :platform_iss }
end

# app/models/project.rb
class Project < ApplicationRecord
  belongs_to :lti_context
  
  validates :name, presence: true
  validates :lti_user_sub, presence: true
  
  # Canvas Assignment ID 배열 (Canvas API로 관리)
  # assignment_ids는 Canvas Assignment ID만 저장
end
```

---

### Step 3: Canvas API 클라이언트 구현

**목표**: Canvas API 호출을 위한 클라이언트 생성

**생성할 파일**:
- `app/services/canvas_api/client.rb`
- `app/services/canvas_api/assignments_client.rb`

**기능**:
- Canvas API Access Token 획득
- Assignment 생성/수정/삭제
- Submission 생성/조회

**코드 예시**:
```ruby
# app/services/canvas_api/client.rb
module CanvasApi
  class Client
    include HTTParty
    
    def initialize(canvas_url, access_token)
      @canvas_url = canvas_url
      @access_token = access_token
      self.class.base_uri canvas_url
      self.class.headers 'Authorization' => "Bearer #{access_token}"
    end
    
    def create_assignment(course_id, params)
      self.class.post(
        "/api/v1/courses/#{course_id}/assignments",
        body: params.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end
    
    def create_submission(course_id, assignment_id, params)
      self.class.post(
        "/api/v1/courses/#{course_id}/assignments/#{assignment_id}/submissions",
        body: params.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end
  end
end
```

---

### Step 4: Canvas API Token 생성

**목표**: LTI Launch 시 받은 정보로 Canvas API Token 생성

**생성할 파일**:
- `app/services/lti/canvas_api_token_generator.rb`

**기능**:
- LTI Claims에서 Canvas 정보 추출
- Canvas API Token 생성 (OAuth 2.0 또는 API Token)

**코드 예시**:
```ruby
# app/services/lti/canvas_api_token_generator.rb
module Lti
  class CanvasApiTokenGenerator
    def self.generate(lti_claims, canvas_url)
      # OAuth 2.0 Client Credentials Grant
      # 또는 Canvas API Token 생성
      # LTI User Sub를 Canvas User ID로 매핑 필요
    end
  end
end
```

---

### Step 5: ProjectService 이식

**목표**: Canvas 의존성 제거하고 Canvas API 호출로 변경

**생성할 파일**:
- `app/services/project_service.rb`

**변경 사항**:
- `context.projects` → `LtiContext.find(...).projects`
- `project.assignments` → Canvas API로 Assignment 조회
- `submissions` → Canvas API로 Submission 조회

**코드 예시**:
```ruby
# app/services/project_service.rb
class ProjectService
  def initialize(lti_context, lti_user_sub, canvas_api_client)
    @lti_context = lti_context
    @lti_user_sub = lti_user_sub
    @canvas_api = canvas_api_client
  end
  
  def projects_with_submission_statistics
    @lti_context.projects.map do |project|
      {
        id: project.id,
        name: project.name,
        assignments: fetch_assignments_from_canvas(project.assignment_ids)
      }
    end
  end
  
  private
  
  def fetch_assignments_from_canvas(assignment_ids)
    # Canvas API로 Assignment 조회
    assignment_ids.map do |assignment_id|
      @canvas_api.get_assignment(@lti_context.context_id, assignment_id)
    end
  end
end
```

---

### Step 6: ProjectBuilder 이식

**목표**: Project 생성 시 Canvas API로 Assignment 생성

**생성할 파일**:
- `app/services/project_builder.rb`

**변경 사항**:
- `create_assignment` → Canvas API로 Assignment 생성
- `project.assignments = assignments` → `project.assignment_ids = [ids]`

**코드 예시**:
```ruby
# app/services/project_builder.rb
class ProjectBuilder
  def initialize(lti_context:, project: nil, lti_user_sub:, canvas_api_client:)
    @lti_context = lti_context
    @project = project
    @lti_user_sub = lti_user_sub
    @canvas_api = canvas_api_client
  end
  
  def create_project(project_params)
    project_name = project_params.delete(:name)
    assignments_params = project_params.delete(:assignments) || []
    
    # Canvas API로 Assignment 생성
    assignment_ids = assignments_params.map do |assignment_params|
      response = @canvas_api.create_assignment(
        @lti_context.context_id,
        assignment_params
      )
      response['id']  # Canvas Assignment ID 저장
    end
    
    # Project 생성 (자체 DB)
    project = Project.new(
      lti_context: @lti_context,
      name: project_name,
      lti_user_sub: @lti_user_sub,
      assignment_ids: assignment_ids
    )
    project.save!
    
    project
  end
end
```

---

### Step 7: ProjectsController 이식

**목표**: LTI 인증 추가 및 Canvas API 연동

**생성할 파일**:
- `app/controllers/projects_controller.rb`

**변경 사항**:
- `require_context`, `require_user` → LTI Launch에서 받은 정보 사용
- `@context.projects` → `@lti_context.projects`
- Canvas API 클라이언트 주입

**코드 예시**:
```ruby
# app/controllers/projects_controller.rb
class ProjectsController < Lti::BaseController
  before_action :set_lti_context
  before_action :set_canvas_api_client
  before_action :check_instructor_role, only: [:new, :create, :edit, :update, :destroy]
  
  def index
    project_service = ProjectService.new(
      @lti_context,
      @lti_claims[:user_sub],
      @canvas_api
    )
    @projects = project_service.projects_with_submission_statistics
  end
  
  def create
    builder = ProjectBuilder.new(
      lti_context: @lti_context,
      lti_user_sub: @lti_claims[:user_sub],
      canvas_api_client: @canvas_api
    )
    project = builder.create_project(project_params)
    
    render json: { id: project.id, name: project.name }, status: :created
  end
  
  private
  
  def set_lti_context
    context_id = @lti_claims[:course_id]
    platform_iss = @lti_claims[:issuer]
    
    @lti_context = LtiContext.find_by(
      context_id: context_id,
      platform_iss: platform_iss
    ) || LtiContext.create!(
      context_id: context_id,
      context_type: 'Course',
      context_title: @lti_claims[:context_title],
      platform_iss: platform_iss,
      canvas_url: Lti::PlatformConfig.canvas_url_for(platform_iss)
    )
  end
  
  def set_canvas_api_client
    canvas_url = @lti_context.canvas_url
    access_token = Lti::CanvasApiTokenGenerator.generate(@lti_claims, canvas_url)
    @canvas_api = CanvasApi::Client.new(canvas_url, access_token)
  end
  
  def check_instructor_role
    unless @lti_claims[:user_role] == :instructor
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
```

---

### Step 8: LaunchController 수정

**목표**: Launch 후 Projects 화면으로 리다이렉트

**수정할 파일**:
- `app/controllers/lti/launch_controller.rb`

**변경 사항**:
- Launch 성공 시 Projects 목록으로 리다이렉트
- LTI Claims를 세션에 저장

**코드 예시**:
```ruby
# app/controllers/lti/launch_controller.rb (수정)
def handle
  # ... 기존 JWT 검증 코드 ...
  
  # LTI Claims 추출
  @lti_claims = extract_lti_claims(payload)
  
  # 세션에 LTI Claims 저장 (API 호출 시 사용)
  session[:lti_claims] = @lti_claims
  
  # Projects 목록으로 리다이렉트
  redirect_to projects_path
end
```

---

### Step 9: 라우팅 추가

**목표**: Projects 관련 라우트 추가

**수정할 파일**:
- `config/routes.rb`

**코드 예시**:
```ruby
# config/routes.rb
Rails.application.routes.draw do
  # LTI Routes
  namespace :lti do
    match "login", to: "login#initiate", via: [:get, :post]
    post "launch", to: "launch#handle"
  end
  
  # Projects Routes
  resources :projects
  
  # Admin Routes
  namespace :admin do
    resources :lti_platforms
  end
  
  root "projects#index"
end
```

---

### Step 10: ERB 뷰 템플릿 구현

**목표**: Rails ERB 템플릿으로 UI 구현 (React 불필요)

**생성할 파일**:
- `app/views/projects/index.html.erb` - 프로젝트 목록
- `app/views/projects/new.html.erb` - 프로젝트 생성 폼
- `app/views/projects/edit.html.erb` - 프로젝트 수정 폼
- `app/views/projects/show.html.erb` - 프로젝트 상세
- `app/views/projects/_form.html.erb` - 공통 폼 partial

**변경 사항**:
- Canvas 프로젝트의 ERB 뷰 참고
- Canvas 의존성 제거 (브레드크럼, 인스턴스 UI 제거)
- LTI Tool 자체 API 호출 (AJAX 또는 form submit)
- Canvas Assignment는 Canvas API로 직접 호출

**코드 예시**:
```erb
<!-- app/views/projects/index.html.erb -->
<div class="container">
  <h1>프로젝트 목록</h1>
  
  <% if @lti_claims[:user_role] == :instructor %>
    <%= link_to "새 프로젝트 생성", new_project_path, class: "btn btn-primary" %>
  <% end %>
  
  <div class="projects-list">
    <% @projects.each do |project| %>
      <div class="project-card">
        <h3><%= project[:name] %></h3>
        <p>과제 수: <%= project[:assignments].count %></p>
        <%= link_to "상세보기", project_path(project[:id]) %>
      </div>
    <% end %>
  </div>
</div>
```

**장점**:
- ✅ React 빌드 과정 불필요
- ✅ 서버 사이드 렌더링으로 빠른 초기 로딩
- ✅ Rails 기본 기능 활용 (form_with, link_to 등)
- ✅ 간단한 AJAX로 동적 기능 구현 가능

---

## ✅ 이식 체크리스트

### 필수 작업
- [ ] Step 1: 데이터베이스 마이그레이션 생성
- [ ] Step 2: 모델 생성
- [ ] Step 3: Canvas API 클라이언트 구현
- [ ] Step 4: Canvas API Token 생성
- [ ] Step 5: ProjectService 이식
- [ ] Step 6: ProjectBuilder 이식
- [ ] Step 7: ProjectsController 이식
- [ ] Step 8: LaunchController 수정
- [ ] Step 9: 라우팅 추가

### 필수 작업 (계속)
- [ ] Step 10: ERB 뷰 템플릿 구현

### 선택 작업
- [ ] Slack 채널 생성 기능 (선택사항)
- [ ] 에러 처리 개선
- [ ] 테스트 작성
- [ ] CSS 스타일링 (Bootstrap 또는 Tailwind)

---

## 🚨 주의사항

### Canvas 의존성 제거
- ❌ `context` (Course 모델) 직접 참조 제거
- ❌ `assignments` 관계 제거
- ❌ `submissions` 관계 제거
- ✅ Canvas API로 Assignment/Submission 관리

### LTI Claims 활용
- LTI Launch 시 받은 정보만 사용
- Canvas User ID는 LTI User Sub로 매핑 필요
- Canvas Course ID는 LTI Context ID 사용

### Canvas API 호출
- Canvas API 경로는 표준화되어 있음 (커머셜/오픈소스 동일)
- OAuth 2.0 또는 API Token 인증 필요
- Rate Limiting 고려

---

## 📝 다음 단계

1. **Step 1부터 순차적으로 진행**
2. **각 단계 완료 후 테스트**
3. **Canvas API 연동 확인**
4. **에러 처리 및 로깅 추가**

---

**작성일**: 2025-01-06  
**작성자**: AI Assistant

