# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Project 모델 (LTI Tool 자체 DB)
# - Canvas 의존성 제거 (context, assignments 관계 제거)
# - Canvas Assignment는 ID 배열로만 참조
#
# 기술적 고려사항:
# - assignment_ids는 PostgreSQL 배열 타입
# - LTI User Sub로 사용자 식별
#
# 사용 시 고려사항:
# - Assignment 데이터는 Canvas DB에 저장 (Canvas API로 관리)
# - Project는 Assignment ID만 참조
class Project < ApplicationRecord
  belongs_to :lti_context
  
  validates :name, presence: true
  validates :lti_user_sub, presence: true
  
  # Canvas Assignment ID 배열 (Canvas API로 관리)
  # assignment_ids는 Canvas Assignment ID만 저장
  # Assignment 데이터는 Canvas DB에 저장되어 있음
end

