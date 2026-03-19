# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas Enrollments API 전용 클라이언트
# - 코스별 사용자 등록 정보 조회 (역할 확인용)
#
# 기술적 고려사항:
# - Canvas API 표준 엔드포인트 사용
# - 코스별 사용자 역할 확인 (StudentEnrollment, TeacherEnrollment 등)
#
# 사용 시 고려사항:
# - CanvasApi::Client를 래핑하여 사용
# - Course ID와 User ID는 LTI Claims에서 가져옴
module CanvasApi
  class EnrollmentsClient
    def initialize(client)
      @client = client
    end

    # 코스의 특정 사용자 등록 정보 조회
    # @param course_id [String] Canvas Course ID
    # @param user_id [String] Canvas User ID
    # @return [Array] Enrollment 목록
    #
    # 예시 반환값:
    #   [
    #     {
    #       "id" => 789,
    #       "user_id" => 456,
    #       "course_id" => 123,
    #       "type" => "StudentEnrollment",
    #       "role" => "Student",
    #       "role_id" => 3,
    #       "enrollment_state" => "active"
    #     }
    #   ]
    def find_user_enrollments(course_id, user_id)
      @client.get("/courses/#{course_id}/enrollments", { user_id: user_id })
    end

    # 코스의 모든 등록 정보 조회
    # @param course_id [String] Canvas Course ID
    # @param params [Hash] 추가 파라미터 (type, role 등)
    # @return [Array] Enrollment 목록
    def list(course_id, params = {})
      @client.get("/courses/#{course_id}/enrollments", params)
    end

    # 코스의 active 학생 목록 조회
    # @param course_id [String] Canvas Course ID
    # @return [Array<Hash>] 학생 정보 배열
    #   [{ user_id:, name:, sortable_name:, login_id:, email: }, ...]
    def list_students(course_id)
      enrollments = list(course_id, {
        'type[]' => 'StudentEnrollment',
        'state[]' => 'active',
        'include[]' => 'email',
        'per_page' => 100
      })

      seen = Set.new
      enrollments.filter_map do |enrollment|
        user = enrollment['user']
        next unless user
        next if seen.include?(user['id'])

        seen << user['id']
        {
          user_id: user['id'],
          name: user['name'],
          sortable_name: user['sortable_name'],
          login_id: user['login_id'],  # Panopto 식별자 (Canvas unique_id)
          email: user['email']          # Zoom 식별자
        }
      end
    end
  end
end
