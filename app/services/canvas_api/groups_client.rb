# frozen_string_literal: true

# Canvas Groups API 클라이언트
# - 그룹 멤버 조회
module CanvasApi
  class GroupsClient
    def initialize(client)
      @client = client
    end

    # 그룹 멤버 조회
    # @param group_id [String] Group ID
    # @return [Array] 그룹 멤버 목록
    #
    # 예시 반환값:
    #   [
    #     { "id" => 123, "name" => "Student 1", "sortable_name" => "1, Student" },
    #     { "id" => 456, "name" => "Student 2", "sortable_name" => "2, Student" }
    #   ]
    def members(group_id)
      @client.get("/groups/#{group_id}/users")
    end

    # 그룹 정보 조회
    # @param group_id [String] Group ID
    # @return [Hash] 그룹 정보
    def find(group_id)
      @client.get("/groups/#{group_id}")
    end
  end
end
