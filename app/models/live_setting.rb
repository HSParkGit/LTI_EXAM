# frozen_string_literal: true

# LIVE(Zoom) 출결 설정 모델
# Canvas의 ZoomSetting 참고
#
# 설계 방향:
# - AttendanceSession과 1:1 관계
# - 참여 시간 기반 출결 인정
# - 출석/지각 임계값(threshold) 설정
#
# 임계값:
# - attendance_threshold: 전체 진행 시간 대비 참여 시간 % (출석 인정)
# - tardiness_threshold: 전체 진행 시간 대비 참여 시간 % (지각 인정)
class LiveSetting < ApplicationRecord
  belongs_to :attendance_session

  validates :attendance_session_id, uniqueness: true
  validates :attendance_threshold, numericality: { in: 1..100, only_integer: true }, allow_nil: true
  validates :tardiness_threshold, numericality: { in: 1..100, only_integer: true }, allow_nil: true
  validates :duration, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  validate :validate_threshold_order

  # 진행 시간을 분 단위로 반환
  def duration_in_minutes
    return nil if duration.nil?
    (duration.to_f / 60).round
  end

  # 세션 종료 시간
  def end_time
    return nil if start_time.blank? || duration.blank?
    start_time + duration.seconds
  end

  # 출석 인정 참여 시간(초)
  def required_duration_for_present
    return nil if duration.blank? || attendance_threshold.blank?
    (duration * attendance_threshold / 100.0).ceil
  end

  # 지각 인정 참여 시간(초)
  def required_duration_for_late
    return nil if duration.blank? || tardiness_threshold.blank?
    (duration * tardiness_threshold / 100.0).ceil
  end

  # 세션 진행 중인지 확인
  def in_progress?(time = Time.current)
    return false if start_time.blank? || duration.blank?
    time >= start_time && time <= end_time
  end

  private

  def validate_threshold_order
    if attendance_threshold.present? && tardiness_threshold.present? && tardiness_threshold >= attendance_threshold
      errors.add(:tardiness_threshold, '지각 기준은 출석 기준보다 낮아야 합니다')
    end
  end
end
