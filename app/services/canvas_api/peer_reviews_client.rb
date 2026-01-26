# frozen_string_literal: true

# Canvas Peer Reviews API 클라이언트
# - 피어 리뷰 목록 조회
# - 학생에게 할당된 피어 리뷰 조회
module CanvasApi
  class PeerReviewsClient
    def initialize(client)
      @client = client
    end

    # Assignment의 모든 피어 리뷰 조회
    # @param course_id [String] Course ID
    # @param assignment_id [String] Assignment ID
    # @param params [Hash] 추가 파라미터 (include 등)
    # @return [Array] 피어 리뷰 목록
    #
    # 반환 예시:
    #   [
    #     {
    #       "assessor_id" => 23,      # 리뷰어 (리뷰하는 사람) ID
    #       "asset_id" => 13,         # Submission ID
    #       "asset_type" => "Submission",
    #       "id" => 1,
    #       "user_id" => 7,           # 리뷰 대상 학생 ID
    #       "workflow_state" => "assigned"  # 또는 "completed"
    #     }
    #   ]
    def list(course_id, assignment_id, params = {})
      query_params = {}
      if params[:include].present?
        query_params[:include] = params[:include].is_a?(Array) ? params[:include] : [params[:include]]
      end
      @client.get("/courses/#{course_id}/assignments/#{assignment_id}/peer_reviews", query_params)
    end

    # 특정 학생에게 할당된 피어 리뷰 조회
    # (assessor_id가 해당 학생인 피어 리뷰만 필터링)
    # @param course_id [String] Course ID
    # @param assignment_id [String] Assignment ID
    # @param user_id [String] Canvas User ID (리뷰어)
    # @return [Array] 해당 학생에게 할당된 피어 리뷰 목록
    def assigned_to_user(course_id, assignment_id, user_id)
      all_reviews = list(course_id, assignment_id, include: ['user'])
      all_reviews.select { |review| review['assessor_id'].to_s == user_id.to_s }
    end
  end
end
