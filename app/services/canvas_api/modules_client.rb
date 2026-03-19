# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas Modules API 전용 클라이언트
# - Module Item(content_tag) 조회 (Panopto/Zoom External Tool 매핑용)
#
# 기술적 고려사항:
# - Module Item은 Canvas의 content_tag와 동일
# - External Tool 타입 아이템 필터링 제공
#
# 사용 시 고려사항:
# - CanvasApi::Client를 래핑하여 사용
# - 출결 세션과 Canvas 컨텐츠 매핑 시 활용
module CanvasApi
  class ModulesClient
    def initialize(client)
      @client = client
    end

    # 코스의 모든 모듈 조회
    # @param course_id [String] Canvas Course ID
    # @return [Array] Module 목록
    #
    # 예시 반환값:
    #   [
    #     {
    #       "id" => 123,
    #       "name" => "1주차",
    #       "position" => 1,
    #       "unlock_at" => "2025-01-01T00:00:00Z",
    #       "items_count" => 5,
    #       "items_url" => "https://canvas.example.com/api/v1/courses/1/modules/123/items"
    #     }
    #   ]
    def list_modules(course_id, params = {})
      @client.get("/courses/#{course_id}/modules", params)
    end

    # 모듈의 아이템(content_tag) 조회
    # @param course_id [String] Canvas Course ID
    # @param module_id [String] Module ID
    # @return [Array] Module Item 목록
    #
    # 예시 반환값:
    #   [
    #     {
    #       "id" => 456,  # content_tag_id
    #       "module_id" => 123,
    #       "position" => 1,
    #       "title" => "1-1 강의영상",
    #       "type" => "ExternalTool",
    #       "external_url" => "https://panopto.example.com/..."
    #     }
    #   ]
    def list_module_items(course_id, module_id, params = {})
      @client.get("/courses/#{course_id}/modules/#{module_id}/items", params)
    end

    # 코스의 모든 모듈 아이템 조회 (한 번에)
    # @param course_id [String] Canvas Course ID
    # @return [Array] 모든 Module Item 목록
    def list_all_module_items(course_id)
      modules = list_modules(course_id)
      modules.flat_map do |mod|
        items = list_module_items(course_id, mod['id'])
        items.map do |item|
          item.merge(
            'module_name' => mod['name'],
            'module_position' => mod['position'],
            'module_unlock_at' => mod['unlock_at']
          )
        end
      end
    end

    # Panopto(VOD) 아이템만 필터링
    # @param course_id [String] Canvas Course ID
    # @return [Array] Panopto External Tool 아이템
    def list_panopto_items(course_id)
      all_items = list_all_module_items(course_id)
      all_items.select do |item|
        item['type'] == 'ExternalTool' && item['external_url'].to_s.downcase.include?('panopto')
      end
    end

    # Zoom(LIVE) 아이템만 필터링
    # @param course_id [String] Canvas Course ID
    # @return [Array] Zoom External URL 아이템
    def list_zoom_items(course_id)
      all_items = list_all_module_items(course_id)
      all_items.select do |item|
        item['type'] == 'ExternalUrl' && item['external_url'].to_s.downcase.include?('zoom')
      end
    end

    # 특정 모듈 아이템 조회
    # @param course_id [String] Canvas Course ID
    # @param module_id [String] Module ID
    # @param item_id [String] Module Item ID (content_tag_id)
    # @return [Hash] Module Item 정보
    def find_module_item(course_id, module_id, item_id)
      @client.get("/courses/#{course_id}/modules/#{module_id}/items/#{item_id}")
    end
  end
end
