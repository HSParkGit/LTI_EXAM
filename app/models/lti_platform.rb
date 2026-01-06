# frozen_string_literal: true

class LtiPlatform < ApplicationRecord
  # Canvas 인스턴스(iss)와 Client ID를 매핑하는 모델
  # 여러 Canvas 인스턴스와 연동할 때 사용
  #
  # Canvas Open Source 특성:
  #   - iss: Canvas가 보내는 발급자 값 (예: https://canvas.instructure.com)
  #   - canvas_url: 실제 Canvas 인스턴스 URL (예: https://your-canvas.ngrok-free.app)
  #     authorization endpoint, token endpoint, JWKS endpoint에 사용
  
  validates :iss, presence: true, uniqueness: true
  validates :client_id, presence: true
  validates :name, length: { maximum: 255 }, allow_nil: true
  validates :canvas_url, format: { with: /\Ahttps?:\/\/.+\z/, message: "must be a valid URL" }, allow_nil: true
  validates :client_secret, presence: true, if: -> { active? }
  validates :canvas_api_token, presence: true, if: -> { active? }
  
  # Client Secret 암호화 저장 (Rails 7.1+)
  # Active Record Encryption을 사용하여 민감 정보 암호화
  encrypts :client_secret if respond_to?(:encrypts)
  encrypts :canvas_api_token if respond_to?(:encrypts)
  
  # 활성화된 Platform만 조회
  scope :active, -> { where(active: true) }
  
  # iss로 조회 (활성화된 것만)
  scope :by_iss, ->(iss) { active.where(iss: iss) }
  
  # 실제 Canvas 인스턴스 URL 반환 (canvas_url이 있으면 그것, 없으면 iss 사용)
  def actual_canvas_url
    canvas_url.presence || iss
  end
end
