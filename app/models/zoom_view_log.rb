# frozen_string_literal: true

#
# Zoom 참여 로그 모델
# 외부 시스템에서 INSERT되는 데이터 조회용
#
# 용도:
# - 학생의 참여 이력 조회 (히스토리 API)
# - 참여 시간 집계
#
class ZoomViewLog < ApplicationRecord
  self.table_name = 'zoom_view_logs'

  # 스코프
  scope :by_content_tag, ->(content_tag_id) { where(content_tag_id: content_tag_id) }
  scope :by_user_email, ->(user_email) { where(user_email: user_email) }
  scope :by_meeting, ->(meeting_id) { where(meeting_id: meeting_id) }
  scope :recent_first, -> { order(created_at: :desc) }

  # 특정 학생의 참여 로그 조회
  def self.for_student(content_tag_id, user_email)
    by_content_tag(content_tag_id)
      .by_user_email(user_email)
      .recent_first
  end

  # 총 참여 시간 (초)
  def self.total_duration(content_tag_id, user_email)
    for_student(content_tag_id, user_email).sum(:duration)
  end
end
