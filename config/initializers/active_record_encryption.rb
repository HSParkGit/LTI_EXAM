# frozen_string_literal: true

# Active Record Encryption 설정
# Client Secret 등 민감 정보 암호화 저장용
#
# 프로덕션 환경에서는 credentials에 키를 추가하는 것을 권장합니다:
#   rails credentials:edit
#   active_record_encryption:
#     primary_key: <32바이트 랜덤 키>
#     deterministic_key: <32바이트 랜덤 키>
#     key_derivation_salt: <랜덤 솔트>
#
# 개발 환경에서는 환경변수 또는 기본 키를 사용합니다.

# 환경변수에서 키를 가져오거나, 없으면 기본 키 사용
primary_key = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY") do
  # 개발 환경용 기본 키 (32바이트 hex 문자열)
  # 프로덕션에서는 반드시 환경변수나 credentials로 관리해야 함
  "0000000000000000000000000000000000000000000000000000000000000000"
end

deterministic_key = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY") do
  "0000000000000000000000000000000000000000000000000000000000000000"
end

key_derivation_salt = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT") do
  "0000000000000000000000000000000000000000000000000000000000000000"
end

Rails.application.config.active_record.encryption.primary_key = primary_key
Rails.application.config.active_record.encryption.deterministic_key = deterministic_key
Rails.application.config.active_record.encryption.key_derivation_salt = key_derivation_salt

