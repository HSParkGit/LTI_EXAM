# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas Assignment Groups API 전용 클라이언트
# - Assignment Group 목록 조회 (프로젝트 생성 시 드롭다운용)
# - Assignment Group 생성 (필요시)
#
# 기술적 고려사항:
# - Assignment Group = Canvas의 과제 카테고리
# - 예: "Assignments", "Quizzes", "Projects" 등
#
# 사용 시 고려사항:
# - CanvasApi::Client를 래핑하여 사용
# - Course ID는 LTI Context ID 사용
module CanvasApi
  class AssignmentGroupsClient
    def initialize(client)
      @client = client
    end

    # Course의 모든 Assignment Group 조회
    # @param course_id [String] Canvas Course ID
    # @return [Array] Assignment Group 목록
    #
    # 예시 반환값:
    #   [
    #     { "id" => 1, "name" => "Assignments", "position" => 1, "group_weight" => 0 },
    #     { "id" => 2, "name" => "Projects", "position" => 2, "group_weight" => 50 }
    #   ]
    def list(course_id)
      @client.get("/courses/#{course_id}/assignment_groups")
    end

    # Assignment Group 조회
    # @param course_id [String] Canvas Course ID
    # @param group_id [String] Assignment Group ID
    # @return [Hash] Assignment Group 정보
    def find(course_id, group_id)
      @client.get("/courses/#{course_id}/assignment_groups/#{group_id}")
    end

    # Assignment Group 생성
    # @param course_id [String] Canvas Course ID
    # @param group_params [Hash] Assignment Group 파라미터
    # @return [Hash] 생성된 Assignment Group 정보
    #
    # 예시:
    #   create(course_id, { name: "Projects", group_weight: 30 })
    def create(course_id, group_params)
      @client.post("/courses/#{course_id}/assignment_groups", group_params)
    end
  end
end
