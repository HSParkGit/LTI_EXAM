# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas Group Categories API 전용 클라이언트
# - Group Category 목록 조회 (그룹 과제 설정용)
# - Group Category 생성 (필요시)
#
# 기술적 고려사항:
# - Group Category = 그룹 과제의 그룹 분류
# - 예: "Project Groups", "Lab Groups" 등
# - 각 Group Category에는 여러 Group이 속함
#
# 사용 시 고려사항:
# - CanvasApi::Client를 래핑하여 사용
# - Course ID는 LTI Context ID 사용
# - 그룹 과제가 아닌 경우 Group Category 불필요
module CanvasApi
  class GroupCategoriesClient
    def initialize(client)
      @client = client
    end

    # Course의 모든 Group Category 조회
    # @param course_id [String] Canvas Course ID
    # @return [Array] Group Category 목록
    #
    # 예시 반환값:
    #   [
    #     {
    #       "id" => 1,
    #       "name" => "Project Groups",
    #       "role" => "communities",
    #       "self_signup" => "enabled",
    #       "context_type" => "Course",
    #       "group_limit" => 4
    #     }
    #   ]
    def list(course_id)
      @client.get("/courses/#{course_id}/group_categories")
    end

    # Group Category 조회
    # @param group_category_id [String] Group Category ID
    # @return [Hash] Group Category 정보
    def find(group_category_id)
      @client.get("/group_categories/#{group_category_id}")
    end

    # Group Category 생성
    # @param course_id [String] Canvas Course ID
    # @param category_params [Hash] Group Category 파라미터
    # @return [Hash] 생성된 Group Category 정보
    #
    # 예시:
    #   create(course_id, {
    #     name: "Project Groups",
    #     self_signup: "enabled",
    #     group_limit: 4
    #   })
    def create(course_id, category_params)
      @client.post("/courses/#{course_id}/group_categories", category_params)
    end

    # Group Category의 모든 Group 조회
    # @param group_category_id [String] Group Category ID
    # @return [Array] Group 목록
    #
    # 예시 반환값:
    #   [
    #     { "id" => 1, "name" => "Group 1", "members_count" => 4 },
    #     { "id" => 2, "name" => "Group 2", "members_count" => 3 }
    #   ]
    def groups(group_category_id)
      @client.get("/group_categories/#{group_category_id}/groups")
    end
  end
end
