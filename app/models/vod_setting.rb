# frozen_string_literal: true

# VOD(Panopto) 출결 설정 모델
# Canvas의 PanoptoSetting 참고
#
# 설계 방향:
# - AttendanceSession과 1:1 관계
# - 진도율 기반 출결 인정
# - 출석/지각 마감 기간 분리 관리
#
# 기간 설정:
# - unlock_at: 열람 시작 시점
# - lock_at: 열람 종료 시점
# - attendance_finish_at: 출석 인정 마감
# - tardiness_finish_at: 지각 인정 마감
class VodSetting < ApplicationRecord
  belongs_to :attendance_session

  validates :attendance_session_id, uniqueness: true
  validates :percent_required, numericality: { in: 0..100, only_integer: true }, allow_nil: true

  validate :validate_date_ranges, if: :allow_attendance?

  # 출석 인정 기간인지 확인
  def within_attendance_period?(time = Time.current)
    return false unless allow_attendance?
    return false if unlock_at.present? && time < unlock_at
    return false if attendance_finish_at.present? && time > attendance_finish_at
    true
  end

  # 지각 인정 기간인지 확인
  def within_tardiness_period?(time = Time.current)
    return false unless allow_tardiness?
    return false if attendance_finish_at.present? && time <= attendance_finish_at
    return false if tardiness_finish_at.present? && time > tardiness_finish_at
    true
  end

  # 열람 가능 기간인지 확인
  def within_view_period?(time = Time.current)
    return true if unlock_at.blank? && lock_at.blank?
    return false if unlock_at.present? && time < unlock_at
    return false if lock_at.present? && time > lock_at
    true
  end

  private

  def validate_date_ranges
    if unlock_at.present? && attendance_finish_at.present? && unlock_at >= attendance_finish_at
      errors.add(:attendance_finish_at, '출석 마감은 열람 시작보다 늦어야 합니다')
    end

    if attendance_finish_at.present? && tardiness_finish_at.present? && attendance_finish_at >= tardiness_finish_at
      errors.add(:tardiness_finish_at, '지각 마감은 출석 마감보다 늦어야 합니다')
    end
  end
end
