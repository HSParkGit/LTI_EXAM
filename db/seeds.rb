# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# LTI Platform 예시 데이터 (개발 환경용)
# 프로덕션에서는 환경변수나 관리자 인터페이스를 통해 등록
if Rails.env.development?
  # Canvas 인스턴스 예시
  # 실제 사용 시 Canvas Developer Key에서 발급받은 Client ID로 교체
  # LtiPlatform.find_or_create_by!(iss: "https://canvas.instructure.com") do |platform|
  #   platform.client_id = "10000000000001"
  #   platform.name = "Canvas Production"
  #   platform.active = true
  # end
end
