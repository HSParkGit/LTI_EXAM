# frozen_string_literal: true

# 설계 방향 및 원칙:
# - LTI Context와 Canvas 코스를 매핑하는 모델
# - 여러 Canvas 인스턴스에서 동일한 코스 ID가 있을 수 있으므로 platform_iss와 함께 관리
# - Canvas API 호출을 위한 canvas_url 저장
#
# 기술적 고려사항:
# - context_id와 platform_iss의 복합 유니크 제약
# - LtiPlatform과의 관계 (belongs_to)
#
# 사용 시 고려사항:
# - LTI Launch 시 자동 생성 또는 조회
# - Canvas API 호출 시 canvas_url 사용
class LtiContext < ApplicationRecord
  belongs_to :lti_platform, foreign_key: :platform_iss, primary_key: :iss
  has_many :projects, dependent: :destroy
  
  validates :context_id, presence: true
  validates :context_type, presence: true
  validates :platform_iss, presence: true
  validates :canvas_url, presence: true, format: { with: /\Ahttps?:\/\/.+\z/ }
  validates :context_id, uniqueness: { scope: :platform_iss, message: "이 코스는 이미 등록되어 있습니다." }
end

