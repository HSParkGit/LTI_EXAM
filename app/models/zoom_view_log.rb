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

  # join_time을 Time 객체로 변환 (KST)
  def join_time_parsed
    return nil unless join_time.present?

    Time.parse(join_time).in_time_zone('Asia/Seoul')
  rescue ArgumentError
    nil
  end

  # leave_time을 Time 객체로 변환 (KST)
  def leave_time_parsed
    return nil unless leave_time.present?

    Time.parse(leave_time).in_time_zone('Asia/Seoul')
  rescue ArgumentError
    nil
  end

  # 참여 시간 범위 문자열 (예: "11:30 AM - 12:00 PM")
  def view_time_range_string
    return '-' unless join_time_parsed && leave_time_parsed

    "#{join_time_parsed.strftime('%I:%M %p')} - #{leave_time_parsed.strftime('%I:%M %p')}"
  end
end
