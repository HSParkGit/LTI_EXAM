# frozen_string_literal: true

class LtiPlatform < ApplicationRecord
  # Canvas 인스턴스(iss)와 Client ID를 매핑하는 모델
  # 여러 Canvas 인스턴스와 연동할 때 사용
  
  validates :iss, presence: true, uniqueness: true
  validates :client_id, presence: true
  validates :name, length: { maximum: 255 }, allow_nil: true
  
  # 활성화된 Platform만 조회
  scope :active, -> { where(active: true) }
  
  # iss로 조회 (활성화된 것만)
  scope :by_iss, ->(iss) { active.where(iss: iss) }
end
