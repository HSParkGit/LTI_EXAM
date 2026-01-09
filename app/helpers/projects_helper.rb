# frozen_string_literal: true

# 설계 방향 및 원칙:
# - ERB 템플릿에서 사용할 헬퍼 메서드 제공
# - 날짜 포맷팅, STEP 상태 계산, 뱃지 렌더링
# - 원본 Canvas의 utils.ts 로직 참고
#
# 기술적 고려사항:
# - Assignment 객체는 Canvas API 응답 해시
# - 날짜는 ISO 8601 형식 문자열
# - STEP 상태: past, current, upcoming
#
# 사용 시 고려사항:
# - ERB 템플릿에서 직접 사용
# - Assignment 해시에서 unlock_at, due_at, lock_at 사용
module ProjectsHelper
  # STEP의 상태를 결정하는 함수
  # @param assignment [Hash] Assignment 객체 (Canvas API 응답)
  # @return [String] 'past', 'current', 'upcoming'
  #
  # 로직:
  # - due_at이 지났으면 'past'
  # - unlock_at이 아직 오지 않았으면 'upcoming'
  # - 그 외는 'current'
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
  rescue ArgumentError => e
    Rails.logger.error "날짜 파싱 실패: #{e.message}"
    'current' # 기본값
  end

  # STEP 상태에 따른 CSS 클래스 반환
  # @param assignment [Hash] Assignment 객체
  # @return [String] CSS 클래스
  def step_status_class(assignment)
    status = get_step_status(assignment)
    "step-#{status}"
  end

  # 날짜를 'MMM D, h:mm A' 형식으로 포맷
  # @param date_string [String] ISO 8601 날짜 문자열
  # @return [String] 포맷된 날짜 (예: 'Nov 1, 2:00 PM')
  #
  # 예시:
  #   format_date('2025-11-01T14:00:00Z') => 'Nov 1, 2:00 PM'
  def format_date(date_string)
    return '-' unless date_string.present?

    date = Time.parse(date_string)
    date.strftime('%b %d, %l:%M %p')
  rescue ArgumentError => e
    Rails.logger.error "날짜 포맷팅 실패: #{e.message}"
    '-'
  end

  # 프로젝트 목록에서 최대 STEP 수 계산
  # @param projects [Array<Hash>] 프로젝트 목록
  # @return [Integer] 최대 STEP 수
  def max_steps_count(projects)
    return 4 if projects.blank? # 기본값

    projects.map { |p| p[:assignments]&.length || 0 }.max || 4
  end

  # 채점 상태 결정 (교수용)
  # @param assignment [Hash] Assignment 객체
  # @return [String, nil] 'Graded', 'Needs Grading', nil
  def grading_status(assignment)
    submitted_count = assignment['submitted_count'] || 0
    graded_count = assignment['graded_count'] || 0
    grading_required = assignment['grading_required'] || 0

    # 아무도 제출하지 않았으면 nil
    return nil if submitted_count.zero?

    # 모두 채점 완료했으면 'Graded'
    return 'Graded' if submitted_count == graded_count

    # 채점이 필요하면 'Needs Grading'
    return 'Needs Grading' if grading_required.positive?

    nil
  end

  # 뱃지 색상 클래스 반환
  # @param badge_type [String] 뱃지 타입 ('submitted', 'graded', 'needs-grading', 'not-submitted')
  # @return [String] CSS 클래스
  def badge_class(badge_type)
    case badge_type
    when 'submitted', 'graded'
      'badge-success' # 녹색
    when 'not-submitted', 'needs-grading'
      'badge-warning' # 노란색
    else
      'badge-secondary' # 회색
    end
  end

  # SpeedGrader URL 생성
  # @param course_id [String] Canvas Course ID
  # @param assignment_id [String] Canvas Assignment ID
  # @param canvas_url [String] Canvas 인스턴스 URL
  # @return [String] SpeedGrader URL
  def speed_grader_url(course_id, assignment_id, canvas_url)
    "#{canvas_url}/courses/#{course_id}/gradebook/speed_grader?assignment_id=#{assignment_id}"
  end

  # Canvas Assignment 페이지 URL 생성
  # @param course_id [String] Canvas Course ID
  # @param assignment_id [String] Canvas Assignment ID
  # @param canvas_url [String] Canvas 인스턴스 URL
  # @return [String] Assignment URL
  def canvas_assignment_url(course_id, assignment_id, canvas_url)
    "#{canvas_url}/courses/#{course_id}/assignments/#{assignment_id}"
  end

  # Canvas Submission 페이지 URL 생성
  # @param course_id [String] Canvas Course ID
  # @param assignment_id [String] Canvas Assignment ID
  # @param user_id [String] Canvas User ID
  # @param canvas_url [String] Canvas 인스턴스 URL
  # @return [String] Submission URL
  def canvas_submission_url(course_id, assignment_id, user_id, canvas_url)
    "#{canvas_url}/courses/#{course_id}/assignments/#{assignment_id}/submissions/#{user_id}"
  end
end
