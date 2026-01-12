# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas Courses API 전용 클라이언트
# - 코스 정보 조회 (과목 이름 등)
#
# 기술적 고려사항:
# - Canvas API 표준 엔드포인트 사용
#
# 사용 시 고려사항:
# - CanvasApi::Client를 래핑하여 사용
# - Course ID는 LTI Context의 canvas_course_id 사용
module CanvasApi
  class CoursesClient
    def initialize(client)
      @client = client
    end

    # Course 조회
    # @param course_id [String] Canvas Course ID
    # @return [Hash] Course 정보
    #
    # 예시 반환값:
    #   {
    #     "id" => 1,
    #     "name" => "Introduction to Computer Science",
    #     "course_code" => "CS101",
    #     "workflow_state" => "available"
    #   }
    def find(course_id)
      @client.get("/courses/#{course_id}")
    end

    # Course 목록 조회 (현재 사용자 기준)
    # @return [Array] Course 목록
    def list
      @client.get("/courses")
    end
  end
end
