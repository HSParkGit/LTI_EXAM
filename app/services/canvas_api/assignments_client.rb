# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas Assignments API 전용 클라이언트
# - Project 생성 시 Assignment 생성
# - Assignment 조회 및 관리
#
# 기술적 고려사항:
# - Canvas API 표준 엔드포인트 사용
# - Course ID는 LTI Context ID 사용
#
# 사용 시 고려사항:
# - CanvasApi::Client를 래핑하여 사용
# - Course ID는 LtiContext.context_id 사용
module CanvasApi
  class AssignmentsClient
    def initialize(client)
      @client = client
    end
    
    # Assignment 생성
    # @param course_id [String] Canvas Course ID
    # @param assignment_params [Hash] Assignment 파라미터
    # @return [Hash] 생성된 Assignment 정보
    def create(course_id, assignment_params)
      # Canvas API는 assignment 키로 래핑된 파라미터를 기대함
      @client.post("/courses/#{course_id}/assignments", { assignment: assignment_params })
    end
    
    # Assignment 조회
    # @param course_id [String] Canvas Course ID
    # @param assignment_id [String] Canvas Assignment ID
    # @return [Hash] Assignment 정보
    def find(course_id, assignment_id)
      @client.get("/courses/#{course_id}/assignments/#{assignment_id}")
    end
    
    # Course의 모든 Assignment 조회
    # @param course_id [String] Canvas Course ID
    # @return [Array] Assignment 목록
    def list(course_id)
      @client.get("/courses/#{course_id}/assignments")
    end
    
    # Assignment 수정
    # @param course_id [String] Canvas Course ID
    # @param assignment_id [String] Canvas Assignment ID
    # @param assignment_params [Hash] 수정할 Assignment 파라미터
    # @return [Hash] 수정된 Assignment 정보
    def update(course_id, assignment_id, assignment_params)
      @client.put("/courses/#{course_id}/assignments/#{assignment_id}", assignment_params)
    end
    
    # Assignment 삭제
    # @param course_id [String] Canvas Course ID
    # @param assignment_id [String] Canvas Assignment ID
    # @return [Hash] 삭제 결과
    def delete(course_id, assignment_id)
      @client.delete("/courses/#{course_id}/assignments/#{assignment_id}")
    end
  end
end

