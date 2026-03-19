# frozen_string_literal: true

class LtiPlatform < ApplicationRecord
  # Canvas 인스턴스(iss)와 Client ID를 매핑하는 모델
  # 여러 Canvas 인스턴스와 연동할 때 사용
  #
  # Canvas Open Source 특성:
  #   - iss: Canvas가 보내는 발급자 값 (예: https://canvas.instructure.com)
  #   - canvas_url: 실제 Canvas 인스턴스 URL (예: https://your-canvas.ngrok-free.app)
  #     authorization endpoint, token endpoint, JWKS endpoint에 사용
  
  validates :iss, presence: true
  validates :client_id, presence: true
  validates :iss, uniqueness: { scope: :client_id, message: "이 ISS와 Client ID 조합은 이미 등록되어 있습니다." }
  validates :name, length: { maximum: 255 }, allow_nil: true
  validates :canvas_url, format: { with: /\Ahttps?:\/\/.+\z/, message: "must be a valid URL" }, allow_nil: true
  validates :client_secret, length: { maximum: 1000 }, allow_blank: true
  validates :canvas_api_token, length: { maximum: 1000 }, allow_blank: true
  
  # Client Secret 암호화 저장 (Rails 7.1+)
  # Active Record Encryption을 사용하여 민감 정보 암호화
  encrypts :client_secret if respond_to?(:encrypts)
  encrypts :canvas_api_token if respond_to?(:encrypts)
  
  # 활성화된 Platform만 조회
  scope :active, -> { where(active: true) }
  
  # iss로 조회 (활성화된 것만)
  # 주의: 같은 iss에 여러 client_id가 있을 수 있으므로, 가능하면 client_id도 함께 지정
  scope :by_iss, ->(iss) { active.where(iss: iss) }
  
  # iss와 client_id로 조회 (활성화된 것만)
  scope :by_iss_and_client_id, ->(iss, client_id) { active.where(iss: iss, client_id: client_id) }
  
  # 실제 Canvas 인스턴스 URL 반환 (canvas_url이 있으면 그것, 없으면 iss 사용)
  def actual_canvas_url
    canvas_url.presence || iss
  end
end
