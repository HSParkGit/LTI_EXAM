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

  # event_time을 Time 객체로 변환 (KST)
  def event_time_parsed
    return nil unless event_time.present?

    Time.parse(event_time).in_time_zone('Asia/Seoul')
  rescue ArgumentError
    nil
  end

  # 시청 시간 범위 계산
  # start_position = 세션 시작으로부터 이 구간까지의 경과 시간(초)
  # seconds_viewed = 이 구간의 실제 시청 시간(초)
  def view_time_range
    return nil unless event_time_parsed && start_position && seconds_viewed

    start_t = event_time_parsed + start_position.seconds
    end_t = start_t + seconds_viewed.seconds
    { start: start_t, end: end_t }
  end

  # 시청 시간 범위 문자열 (예: "11:30 AM - 12:00 PM")
  def view_time_range_string
    range = view_time_range
    return '-' unless range

    "#{range[:start].strftime('%I:%M %p')} - #{range[:end].strftime('%I:%M %p')}"
  end
end
