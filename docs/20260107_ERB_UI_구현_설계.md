# ERB UI 구현 설계

## 📋 개요

원본 Canvas의 React 컴포넌트(`hy_projects`, `hy_project_new_v2`, `hy_project_show`)를 참고하여 ERB 템플릿으로 구현하는 설계 문서입니다.

**참고 파일**:
- `canvas/ui/features/hy_projects/` - 프로젝트 목록
- `canvas/ui/features/hy_project_new_v2/` - 프로젝트 생성
- `canvas/ui/features/hy_project_show/` - 프로젝트 상세

---

## 🎯 구현 목표

원본 Canvas Project 기능을 ERB 템플릿으로 구현하여 동일한 사용자 경험 제공

---

## 📐 1. 프로젝트 목록 (Projects Index)

### 1.1 기능 요구사항

#### 프로젝트 분류
- **Current Projects**: 진행 중인 프로젝트 (1개 이상의 STEP이 마감일 전)
- **Upcoming Projects**: 시작 전 프로젝트 (모든 STEP이 시작일 전)
- **Past Projects**: 종료된 프로젝트 (모든 STEP이 마감일 지남)
- **Unpublished Projects**: 미공개 프로젝트 (학생은 볼 수 없음)

#### STEP 표시
- 각 Assignment를 STEP 1, STEP 2...로 표시
- STEP별 상태 표시:
  - **Past**: 마감일 지남 (회색)
  - **Current**: 진행 중 (강조)
  - **Upcoming**: 시작 전 (연한 회색)

#### Submission 통계
- **교수용**:
  - 제출 수 / 미제출 수
  - 채점 완료 수 / 채점 필요 수
  - 뱃지: "Graded" (초록) / "Needs Grading" (노랑)
- **학생용**:
  - 본인 제출 여부
  - 뱃지: "Submitted" (초록) / "Not Submitted" (노랑)

#### 날짜 표시
- 프로젝트 시작일: 첫 번째 STEP의 `unlock_at`
- 프로젝트 마감일: 마지막 STEP의 `due_at`
- 프로젝트 종료일: 마지막 STEP의 `lock_at`
- 형식: "MMM D, h:mm A" (예: "Nov 1, 2:00 PM")

### 1.2 데이터 구조

```ruby
# ProjectService 수정 필요
class ProjectService
  def projects_with_statistics
    # 프로젝트 분류 로직
    # Submission 통계 포함
    # STEP별 상태 계산
  end
  
  private
  
  def classify_projects(projects)
    current_date = Time.current
    
    {
      current: projects.select { |p| has_active_step?(p, current_date) },
      upcoming: projects.select { |p| all_steps_not_started?(p, current_date) },
      past: projects.select { |p| all_steps_completed?(p, current_date) },
      unpublished: projects.select { |p| !p.published? }
    }
  end
  
  def get_step_status(assignment)
    # past / current / upcoming 반환
  end
end
```

### 1.3 ERB 템플릿 구조

```erb
<!-- app/views/projects/index.html.erb -->
<div class="projects-page">
  <header>
    <h1>Projects</h1>
    <%= link_to '+ Create', new_project_path, class: 'create-button' %>
  </header>
  
  <!-- Current Projects -->
  <%= render 'projects_section', 
      title: 'Current Projects',
      projects: @current_projects,
      section_type: 'current' %>
  
  <!-- Upcoming Projects -->
  <%= render 'projects_section',
      title: 'Upcoming Projects',
      projects: @upcoming_projects,
      section_type: 'upcoming' %>
  
  <!-- Unpublished Projects (교수만) -->
  <% unless @lti_claims[:user_role] == :student %>
    <%= render 'projects_section',
        title: 'Unpublished Projects',
        projects: @unpublished_projects,
        section_type: 'unpublished' %>
  <% end %>
  
  <!-- Past Projects -->
  <%= render 'projects_section',
      title: 'Past Projects',
      projects: @past_projects,
      section_type: 'past' %>
</div>
```

### 1.4 Partial: `_projects_section.html.erb`

```erb
<!-- app/views/projects/_projects_section.html.erb -->
<% if projects.any? %>
  <section class="projects-section">
    <h2><%= title %></h2>
    
    <table class="projects-table">
      <thead>
        <tr>
          <th class="project-name-col">Project Name</th>
          <% max_steps.times do |i| %>
            <th class="step-col">STEP <%= i + 1 %></th>
          <% end %>
        </tr>
      </thead>
      <tbody>
        <% projects.each do |project| %>
          <tr>
            <!-- 프로젝트명 셀 -->
            <td class="project-name-cell">
              <%= link_to project.name, project_path(project) %>
              <div class="project-dates">
                Start <%= format_date(project.assignments.first&.unlock_at) %> - 
                Due <%= format_date(project.assignments.last&.due_at) %> / 
                End <%= format_date(project.assignments.last&.lock_at) %>
              </div>
              <div class="project-actions">
                <%= link_to 'Edit', edit_project_path(project) %>
                <%= button_to 'Delete', project_path(project), method: :delete %>
              </div>
            </td>
            
            <!-- STEP 셀들 -->
            <% max_steps.times do |i| %>
              <% assignment = project.assignments[i] %>
              <td class="step-cell <%= step_status_class(assignment) %>">
                <% if assignment %>
                  <%= render 'step_badge', assignment: assignment %>
                  <%= render 'submission_badge', 
                      assignment: assignment,
                      is_student: @lti_claims[:user_role] == :student %>
                <% end %>
              </td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
<% end %>
```

### 1.5 Partial: `_step_badge.html.erb`

```erb
<!-- app/views/projects/_step_badge.html.erb -->
<% status = get_step_status(assignment) %>
<span class="step-badge <%= status %>">
  <%= status.capitalize %>
</span>
```

### 1.6 Partial: `_submission_badge.html.erb`

```erb
<!-- app/views/projects/_submission_badge.html.erb -->
<% if is_student %>
  <!-- 학생용: 제출 여부 -->
  <% if assignment.is_submitted %>
    <span class="badge submitted">Submitted</span>
  <% else %>
    <span class="badge not-submitted">Not Submitted</span>
  <% end %>
<% else %>
  <!-- 교수용: 채점 상태 -->
  <% if assignment.submitted_count > 0 %>
    <% if assignment.submitted_count == assignment.graded_count %>
      <span class="badge graded">Graded</span>
    <% elsif assignment.grading_required > 0 %>
      <span class="badge needs-grading">Needs Grading</span>
    <% end %>
  <% end %>
<% end %>
```

### 1.7 Helper 메서드

```ruby
# app/helpers/projects_helper.rb
module ProjectsHelper
  def get_step_status(assignment)
    return 'empty' unless assignment
    
    current_date = Time.current
    unlock_at = assignment['unlock_at'] ? Time.parse(assignment['unlock_at']) : nil
    due_at = assignment['due_at'] ? Time.parse(assignment['due_at']) : nil
    
    if due_at && current_date > due_at
      'past'
    elsif unlock_at && current_date < unlock_at
      'upcoming'
    else
      'current'
    end
  end
  
  def step_status_class(assignment)
    status = get_step_status(assignment)
    "step-#{status}"
  end
  
  def format_date(date_string)
    return '-' unless date_string
    Time.parse(date_string).strftime('%b %d, %l:%M %p')
  end
  
  def max_steps_count(projects)
    projects.map { |p| p.assignments&.length || 0 }.max || 4
  end
end
```

---

## 📝 2. 프로젝트 생성 (Projects New)

### 2.1 기능 요구사항

#### Step Generator
- 여러 Assignment 생성 가능
- STEP 추가/삭제 기능
- STEP별 상세 설정

#### Assignment 상세 설정
- **기본 정보**:
  - 이름 (title)
  - 설명 (description) - Rich Content Editor
- **일정**:
  - 시작일 (unlock_at)
  - 마감일 (due_at)
  - 종료일 (lock_at)
- **점수**:
  - 점수 (points_possible)
  - 채점 방식 (grading_type)
- **제출 설정**:
  - 제출 타입 (submission_types)
  - 허용 확장자 (allowed_extensions)
  - 제출 횟수 제한 (allowed_attempts)
- **Peer Review**:
  - Peer Review 활성화
  - Peer Review 수
  - Peer Review 마감일
- **기타**:
  - Assignment Group
  - Group Category
  - Published 상태

### 2.2 ERB 템플릿 구조

```erb
<!-- app/views/projects/new.html.erb -->
<%= form_with model: @project, url: projects_path, local: true do |form| %>
  <div class="project-form">
    <!-- 프로젝트 이름 -->
    <div class="form-group">
      <%= form.label :name, 'Project Name' %>
      <%= form.text_field :name, required: true %>
    </div>
    
    <!-- Step Generator -->
    <div class="step-generator">
      <div class="step-list">
        <% @steps.each_with_index do |step, index| %>
          <%= render 'step_form', step: step, index: index, form: form %>
        <% end %>
      </div>
      <button type="button" class="add-step-btn">+ Add Step</button>
    </div>
    
    <!-- 공통 설정 -->
    <div class="common-settings">
      <%= form.label :assignment_group_id, 'Assignment Group' %>
      <%= form.select :assignment_group_id, @assignment_groups %>
      
      <%= form.label :group_category_id, 'Group Category' %>
      <%= form.select :group_category_id, @group_categories %>
      
      <%= form.check_box :publish %>
      <%= form.label :publish, 'Publish immediately' %>
    </div>
    
    <%= form.submit 'Create Project' %>
  </div>
<% end %>
```

### 2.3 Partial: `_step_form.html.erb`

```erb
<!-- app/views/projects/_step_form.html.erb -->
<div class="step-form" data-step-index="<%= index %>">
  <div class="step-header">
    <h3>STEP <%= index + 1 %></h3>
    <button type="button" class="remove-step-btn">Remove</button>
  </div>
  
  <div class="step-content">
    <%= fields_for "project[assignments][#{index}]", step do |assignment_form| %>
      <!-- Assignment 기본 정보 -->
      <%= assignment_form.text_field :title, placeholder: 'Step Name' %>
      <%= assignment_form.text_area :description, class: 'rce-editor' %>
      
      <!-- 일정 -->
      <div class="date-fields">
        <%= assignment_form.datetime_local_field :unlock_at, label: 'Start Date' %>
        <%= assignment_form.datetime_local_field :due_at, label: 'Due Date' %>
        <%= assignment_form.datetime_local_field :lock_at, label: 'End Date' %>
      </div>
      
      <!-- 점수 -->
      <div class="points-field">
        <%= assignment_form.number_field :points_possible, min: 0, step: 0.1 %>
        <%= assignment_form.select :grading_type, 
            [['Points', 'points'], ['Pass/Fail', 'pass_fail'], ['Not Graded', 'not_graded']] %>
      </div>
      
      <!-- 제출 설정 -->
      <div class="submission-settings">
        <%= assignment_form.check_box :submission_types, 
            { multiple: true }, 'online_url', nil %>
        <%= assignment_form.label :submission_types, 'URL' %>
        
        <%= assignment_form.check_box :submission_types, 
            { multiple: true }, 'online_upload', nil %>
        <%= assignment_form.label :submission_types, 'File Upload' %>
        
        <%= assignment_form.text_field :allowed_extensions, 
            placeholder: 'pdf, doc, docx' %>
        <%= assignment_form.number_field :allowed_attempts, min: 1 %>
      </div>
      
      <!-- Peer Review -->
      <div class="peer-review-settings">
        <%= assignment_form.check_box :peer_reviews %>
        <%= assignment_form.label :peer_reviews, 'Enable Peer Review' %>
        
        <%= assignment_form.number_field :peer_review_count, min: 1 %>
        <%= assignment_form.datetime_local_field :peer_reviews_due_at %>
      </div>
    <% end %>
  </div>
</div>
```

---

## 📄 3. 프로젝트 상세 (Projects Show)

### 3.1 기능 요구사항

#### 교수/학생 뷰 분리
- **교수용**: Assignment별 Submission 목록, 채점 기능
- **학생용**: 본인 제출 상태, 제출 기능

#### Assignment 그룹 표시
- Assignment를 STEP으로 표시
- 각 STEP별 상태 및 통계

#### Submission 관리
- 교수: 모든 학생의 Submission 조회
- 학생: 본인 Submission 조회 및 제출

### 3.2 ERB 템플릿 구조

```erb
<!-- app/views/projects/show.html.erb -->
<div class="project-show">
  <header>
    <h1><%= @project.name %></h1>
    <% if @lti_claims[:user_role] == :instructor %>
      <%= link_to 'Edit', edit_project_path(@project) %>
      <%= button_to 'Delete', project_path(@project), method: :delete %>
    <% end %>
  </header>
  
  <% if @lti_claims[:user_role] == :instructor %>
    <%= render 'instructor_view', project: @project %>
  <% else %>
    <%= render 'student_view', project: @project %>
  <% end %>
</div>
```

### 3.3 Partial: `_instructor_view.html.erb`

```erb
<!-- app/views/projects/_instructor_view.html.erb -->
<div class="assignment-groups">
  <% @project_data[:assignments].each_with_index do |assignment, index| %>
    <div class="assignment-group">
      <header>
        <h2>STEP <%= index + 1 %>: <%= assignment['name'] %></h2>
        <div class="assignment-stats">
          Submitted: <%= assignment['submitted_count'] || 0 %> / 
          Unsubmitted: <%= assignment['unsubmitted_count'] || 0 %> /
          Graded: <%= assignment['graded_count'] || 0 %>
        </div>
      </header>
      
      <%= render 'assignment_submissions', 
          assignment: assignment,
          submissions: @submissions[assignment['id']] %>
    </div>
  <% end %>
</div>
```

### 3.4 Partial: `_student_view.html.erb`

```erb
<!-- app/views/projects/_student_view.html.erb -->
<div class="student-assignments">
  <% @project_data[:assignments].each_with_index do |assignment, index| %>
    <div class="assignment-card">
      <h3>STEP <%= index + 1 %>: <%= assignment['name'] %></h3>
      
      <div class="assignment-info">
        <p>Due: <%= format_date(assignment['due_at']) %></p>
        <p>Points: <%= assignment['points_possible'] %></p>
      </div>
      
      <div class="submission-status">
        <% if assignment['is_submitted'] %>
          <span class="badge submitted">Submitted</span>
        <% else %>
          <span class="badge not-submitted">Not Submitted</span>
          <%= link_to 'Submit', '#', class: 'submit-btn' %>
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

---

## 🔧 4. 백엔드 구현 필요사항

### 4.1 ProjectService 확장

```ruby
# app/services/project_service.rb
class ProjectService
  def projects_with_statistics
    projects = @lti_context.projects.order(created_at: :desc)
    
    # Canvas API로 Assignment 정보 조회
    projects_with_assignments = projects.map do |project|
      assignments = fetch_assignments_with_statistics(project)
      
      {
        id: project.id,
        name: project.name,
        published: get_published_status(assignments),
        assignments: assignments
      }
    end
    
    # 프로젝트 분류
    classify_projects(projects_with_assignments)
  end
  
  private
  
  def fetch_assignments_with_statistics(project)
    course_id = @lti_context.canvas_course_id
    
    project.assignment_ids.map do |assignment_id|
      assignment = @assignments_client.find(course_id, assignment_id)
      
      # Submission 통계 추가
      if @lti_claims[:user_role] == :instructor
        add_instructor_statistics(assignment, course_id, assignment_id)
      else
        add_student_status(assignment, course_id, assignment_id)
      end
    end
  end
  
  def add_instructor_statistics(assignment, course_id, assignment_id)
    # Canvas API로 Submission 통계 조회
    # GET /api/v1/courses/:course_id/assignments/:assignment_id/submissions
    submissions = @canvas_api.get(
      "/courses/#{course_id}/assignments/#{assignment_id}/submissions",
      { include: ['submission_history'] }
    )
    
    assignment.merge({
      submitted_count: submissions.count { |s| s['submitted_at'].present? },
      unsubmitted_count: submissions.count { |s| s['submitted_at'].blank? },
      graded_count: submissions.count { |s| s['workflow_state'] == 'graded' },
      grading_required: submissions.count { |s| 
        s['submitted_at'].present? && s['workflow_state'] != 'graded' 
      }
    })
  end
  
  def add_student_status(assignment, course_id, assignment_id)
    # Canvas API로 본인 Submission 조회
    # GET /api/v1/courses/:course_id/assignments/:assignment_id/submissions/:user_id
    user_id = @lti_claims[:canvas_user_id]
    
    begin
      submission = @canvas_api.get(
        "/courses/#{course_id}/assignments/#{assignment_id}/submissions/#{user_id}"
      )
      
      assignment.merge({
        is_submitted: submission['submitted_at'].present?
      })
    rescue CanvasApi::Client::ApiError
      assignment.merge({ is_submitted: false })
    end
  end
  
  def classify_projects(projects)
    current_date = Time.current
    
    {
      current: projects.select { |p| has_active_step?(p, current_date) },
      upcoming: projects.select { |p| all_steps_not_started?(p, current_date) },
      past: projects.select { |p| all_steps_completed?(p, current_date) },
      unpublished: projects.select { |p| !p.published? }
    }
  end
  
  def has_active_step?(project, current_date)
    project[:assignments].any? do |assignment|
      due_at = assignment['due_at'] ? Time.parse(assignment['due_at']) : nil
      unlock_at = assignment['unlock_at'] ? Time.parse(assignment['unlock_at']) : nil
      
      (unlock_at.nil? || current_date >= unlock_at) &&
      (due_at.nil? || current_date <= due_at)
    end
  end
  
  def all_steps_not_started?(project, current_date)
    return false if project[:assignments].empty?
    
    project[:assignments].all? do |assignment|
      unlock_at = assignment['unlock_at'] ? Time.parse(assignment['unlock_at']) : nil
      unlock_at && current_date < unlock_at
    end
  end
  
  def all_steps_completed?(project, current_date)
    return false if project[:assignments].empty?
    
    project[:assignments].all? do |assignment|
      due_at = assignment['due_at'] ? Time.parse(assignment['due_at']) : nil
      due_at && current_date > due_at
    end
  end
  
  def get_published_status(assignments)
    assignments.first&.dig('workflow_state') == 'published'
  end
end
```

### 4.2 Canvas API Client 확장

```ruby
# app/services/canvas_api/submissions_client.rb
module CanvasApi
  class SubmissionsClient
    def initialize(client)
      @client = client
    end
    
    # Assignment의 모든 Submission 조회
    def list(course_id, assignment_id, params = {})
      @client.get(
        "/courses/#{course_id}/assignments/#{assignment_id}/submissions",
        params
      )
    end
    
    # 특정 사용자의 Submission 조회
    def find(course_id, assignment_id, user_id)
      @client.get(
        "/courses/#{course_id}/assignments/#{assignment_id}/submissions/#{user_id}"
      )
    end
  end
end
```

### 4.3 ProjectBuilder 확장

```ruby
# app/services/project_builder.rb
class ProjectBuilder
  def create_project(project_params)
    # 여러 Assignment 생성
    assignments = project_params[:assignments].map do |assignment_params|
      create_assignment(assignment_params)
    end
    
    # Project 생성
    project = Project.new(
      lti_context: @lti_context,
      name: project_params[:name],
      lti_user_sub: @lti_user_sub,
      assignment_ids: assignments.map { |a| a['id'].to_s }
    )
    
    project.save!
    project
  end
  
  private
  
  def create_assignment(assignment_params)
    course_id = @lti_context.canvas_course_id
    
    assignment_data = {
      assignment: {
        name: assignment_params[:title],
        description: assignment_params[:description],
        due_at: assignment_params[:due_at],
        unlock_at: assignment_params[:unlock_at],
        lock_at: assignment_params[:lock_at],
        points_possible: assignment_params[:points_possible],
        grading_type: assignment_params[:grading_type],
        submission_types: assignment_params[:submission_types] || ['online_url', 'online_upload'],
        allowed_extensions: assignment_params[:allowed_extensions],
        allowed_attempts: assignment_params[:allowed_attempts],
        workflow_state: assignment_params[:publish] ? 'published' : 'unpublished',
        # Peer Review 설정
        peer_reviews: assignment_params[:peer_reviews] || false,
        peer_review_count: assignment_params[:peer_review_count],
        peer_reviews_due_at: assignment_params[:peer_reviews_due_at]
      }
    }
    
    @assignments_client.create(course_id, assignment_data[:assignment])
  end
end
```

---

## 🎨 5. 스타일링

### 5.1 CSS 클래스 구조

```css
/* 프로젝트 목록 */
.projects-page {
  padding: 24px;
}

.projects-section {
  margin-bottom: 30px;
}

.projects-table {
  width: 100%;
  border-collapse: collapse;
}

.project-name-col {
  width: 616px;
  position: sticky;
  left: 0;
  background: white;
  z-index: 10;
}

.step-col {
  width: 198px;
  text-align: center;
}

.step-cell {
  padding: 16px 20px;
  text-align: center;
}

.step-cell.step-past {
  background: white;
  color: rgba(70, 71, 76, 0.2);
}

.step-cell.step-current {
  background: rgba(112, 115, 124, 0.08);
  color: rgba(70, 71, 76, 0.84);
  font-weight: bold;
}

.step-cell.step-upcoming {
  background: white;
  color: rgba(70, 71, 76, 0.68);
}

/* 뱃지 */
.badge {
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 12px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.badge.submitted,
.badge.graded {
  background: #d1e7dd;
  color: #0f5132;
}

.badge.not-submitted,
.badge.needs-grading {
  background: #fff3cd;
  color: #856404;
}
```

---

## 📋 6. 구현 체크리스트

### Phase 1: 데이터 구조 및 서비스
- [ ] `ProjectService`에 `projects_with_statistics` 메서드 추가
- [ ] 프로젝트 분류 로직 구현 (Current/Upcoming/Past/Unpublished)
- [ ] STEP 상태 계산 로직 구현
- [ ] Submission 통계 조회 로직 구현 (교수/학생 분기)
- [ ] `CanvasApi::SubmissionsClient` 구현

### Phase 2: 프로젝트 목록 UI
- [ ] `projects/index.html.erb` 수정 (섹션별 분류)
- [ ] `_projects_section.html.erb` Partial 생성
- [ ] `_step_badge.html.erb` Partial 생성
- [ ] `_submission_badge.html.erb` Partial 생성
- [ ] `ProjectsHelper`에 헬퍼 메서드 추가
- [ ] CSS 스타일링

### Phase 3: 프로젝트 생성 UI
- [ ] `projects/new.html.erb` 수정 (Step Generator 추가)
- [ ] `_step_form.html.erb` Partial 생성
- [ ] JavaScript로 STEP 추가/삭제 기능
- [ ] Assignment 상세 설정 필드 추가
- [ ] `ProjectBuilder` 수정 (여러 Assignment 생성)

### Phase 4: 프로젝트 상세 UI
- [ ] `projects/show.html.erb` 수정 (교수/학생 분기)
- [ ] `_instructor_view.html.erb` Partial 생성
- [ ] `_student_view.html.erb` Partial 생성
- [ ] `_assignment_submissions.html.erb` Partial 생성

### Phase 5: 테스트 및 개선
- [ ] 각 뷰 테스트
- [ ] Submission 통계 정확성 검증
- [ ] 날짜 포맷팅 검증
- [ ] 반응형 디자인 확인

---

## 🔗 참고 문서

- `docs/MVP_범위_및_의사결정.md` - MVP 범위 정의
- `docs/PROJECT_이식_계획.md` - 프로젝트 이식 계획
- `docs/추가_설계_필요사항.md` - 추가 설계 사항
- `canvas/ui/features/hy_projects/` - 원본 React 컴포넌트
- `canvas/ui/features/hy_project_new_v2/` - 원본 생성 폼
- `canvas/ui/features/hy_project_show/` - 원본 상세 뷰

---

**작성일**: 2026-01-06  
**작성자**: AI Assistant

