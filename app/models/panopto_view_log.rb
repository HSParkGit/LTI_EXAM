# frozen_string_literal: true

#
# Panopto 시청 로그 모델
# 외부 시스템에서 INSERT되는 데이터 조회용
#
# 용도:
# - 학생의 시청 이력 조회 (히스토리 API)
# - 시청 시간 집계
#
class PanoptoViewLog < ApplicationRecord
  self.table_name = 'panopto_view_logs'

  # 스코프
  scope :by_content_tag, ->(content_tag_id) { where(content_tag_id: content_tag_id) }
  scope :by_user_name, ->(user_name) { where(user_name: user_name) }
  scope :recent_first, -> { order(created_at: :desc) }

  # 특정 학생의 시청 로그 조회
  def self.for_student(content_tag_id, user_name)
    by_content_tag(content_tag_id)
      .by_user_name(user_name)
      .recent_first
  end

  # 총 시청 시간 (초)
  def self.total_seconds_viewed(content_tag_id, user_name)
    for_student(content_tag_id, user_name).sum(:seconds_viewed)
  end
end
