# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Canvas API 호출을 위한 Personal Access Token 저장
# - 사용자가 Canvas에서 직접 발급받아 입력
# - Client Credentials Grant 대신 Personal Access Token 사용
#
# 기술적 고려사항:
# - Personal Access Token은 암호화 저장
# - Client Secret과 별도로 관리
#
# 사용 시 고려사항:
# - Canvas에서 Personal Access Token 발급 필요
# - 토큰 만료 시 수동 갱신 필요 (나중에 자동화 가능)
class AddCanvasApiTokenToLtiPlatforms < ActiveRecord::Migration[7.1]
  def change
    add_column :lti_platforms, :canvas_api_token, :string, null: true, comment: 'Canvas Personal Access Token (암호화 저장)'
  end
end

