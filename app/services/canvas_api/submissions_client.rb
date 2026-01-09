# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas Submissions API 전용 클라이언트
# - 제출물 통계 조회 (교수용)
# - 학생 개별 제출물 조회 (학생용)
#
# 기술적 고려사항:
# - Canvas API 표준 엔드포인트 사용
# - include 파라미터로 추가 정보 조회 가능
#
# 사용 시 고려사항:
# - CanvasApi::Client를 래핑하여 사용
# - Course ID와 Assignment ID는 LTI Context에서 가져옴
module CanvasApi
  class SubmissionsClient
    def initialize(client)
      @client = client
    end

    # Assignment의 모든 Submission 조회 (교수용)
    # @param course_id [String] Canvas Course ID
    # @param assignment_id [String] Canvas Assignment ID
    # @param params [Hash] 추가 파라미터 (include 등)
    # @return [Array] Submission 목록
    #
    # 예시:
    #   list(course_id, assignment_id, include: ['submission_history', 'user'])
    def list(course_id, assignment_id, params = {})
      @client.get("/courses/#{course_id}/assignments/#{assignment_id}/submissions", params)
    end

    # 특정 사용자의 Submission 조회 (학생용)
    # @param course_id [String] Canvas Course ID
    # @param assignment_id [String] Canvas Assignment ID
    # @param user_id [String] Canvas User ID
    # @return [Hash] Submission 정보
    #
    # 예시:
    #   find(course_id, assignment_id, canvas_user_id)
    def find(course_id, assignment_id, user_id)
      @client.get("/courses/#{course_id}/assignments/#{assignment_id}/submissions/#{user_id}")
    end

    # Assignment의 모든 Submission 요약 통계 조회
    # @param course_id [String] Canvas Course ID
    # @param assignment_id [String] Canvas Assignment ID
    # @return [Hash] 통계 정보
    #   { submitted_count, unsubmitted_count, graded_count, grading_required }
    def statistics(course_id, assignment_id)
      submissions = list(course_id, assignment_id)

      {
        submitted_count: submissions.count { |s| s['submitted_at'].present? },
        unsubmitted_count: submissions.count { |s| s['submitted_at'].blank? },
        graded_count: submissions.count { |s| s['workflow_state'] == 'graded' },
        grading_required: submissions.count { |s| s['submitted_at'].present? && s['workflow_state'] != 'graded' }
      }
    end
  end
end
