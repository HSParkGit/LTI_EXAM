# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas API 인증을 위한 Client Secret 추가
# - 기존 데이터 호환성을 위해 null 허용
# - 보안을 고려한 암호화 저장 (모델에서 처리)
#
# 기술적 고려사항:
# - null: true로 시작하여 기존 데이터와 호환
# - 이후 not null 제약조건 추가 가능
#
# 사용 시 고려사항:
# - Client Secret은 민감 정보이므로 암호화 저장 필요
# - 환경변수 fallback도 지원 (CanvasApiTokenGenerator에서 처리)
class AddClientSecretToLtiPlatforms < ActiveRecord::Migration[7.1]
  def change
    add_column :lti_platforms, :client_secret, :string, null: true, comment: 'Canvas Developer Key의 Client Secret (암호화 저장)'
  end
end

