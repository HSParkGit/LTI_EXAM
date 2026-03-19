# frozen_string_literal: true

#
# Panopto 출결 결과 모델
# Canvas 원본 로직 포팅
#
# 설계:
# - 외부 시스템에서 INSERT되는 데이터 + 교수 강제 변경
# - user_name이 학생 식별자 (Canvas unique_id = LTI login_id)
# - teacher_forced_change로 우선순위 처리
#
class PanoptoViewResult < ApplicationRecord
  self.table_name = 'panopto_view_results'

  # 출결 상태 상수 (Canvas 원본과 동일)
  ATTENDANCE_STATE_PENDING = 0   # 미결
  ATTENDANCE_STATE_ABSENT = 1    # 결석
  ATTENDANCE_STATE_LATE = 2      # 지각
  ATTENDANCE_STATE_EXCUSED = 3   # 공결
  ATTENDANCE_STATE_PRESENT = 4   # 출석

  ATTENDANCE_STATES = [
    ATTENDANCE_STATE_PENDING,
    ATTENDANCE_STATE_ABSENT,
    ATTENDANCE_STATE_LATE,
    ATTENDANCE_STATE_EXCUSED,
    ATTENDANCE_STATE_PRESENT
  ].freeze

  STATE_LABELS = {
    ATTENDANCE_STATE_PENDING => '미결',
    ATTENDANCE_STATE_ABSENT => '결석',
    ATTENDANCE_STATE_LATE => '지각',
    ATTENDANCE_STATE_EXCUSED => '공결',
    ATTENDANCE_STATE_PRESENT => '출석'
  }.freeze

  # Validations
  validates :content_tag_id, presence: true
  validates :user_id, presence: true
  validates :user_name, presence: true
  validates :session_id, presence: true
  validates :attendance_state, inclusion: { in: ATTENDANCE_STATES }

  # 스코프
  scope :by_content_tag, ->(content_tag_id) { where(content_tag_id: content_tag_id) }
  scope :by_user_name, ->(user_name) { where(user_name: user_name) }
  scope :by_content_tags, ->(content_tag_ids) { where(content_tag_id: content_tag_ids) }

  # 교수 강제 변경 관련 스코프
  scope :teacher_forced, -> { where(teacher_forced_change: 1) }
  scope :not_teacher_forced, -> { where(teacher_forced_change: 0) }

  # 우선순위 정렬 (교수 강제 변경 우선, 최신순)
  scope :priority_ordered, -> { order(teacher_forced_change: :desc, created_at: :desc) }

  # 상태 확인 메서드
  def pending?
    attendance_state == ATTENDANCE_STATE_PENDING
  end

  def absent?
    attendance_state == ATTENDANCE_STATE_ABSENT
  end

  def late?
    attendance_state == ATTENDANCE_STATE_LATE
  end

  def excused?
    attendance_state == ATTENDANCE_STATE_EXCUSED
  end

  def present?
    attendance_state == ATTENDANCE_STATE_PRESENT
  end

  def teacher_forced?
    teacher_forced_change == 1
  end

  # 상태 텍스트
  def attendance_state_text
    STATE_LABELS[attendance_state] || '알 수 없음'
  end

  # 출결 타입 (VOD)
  def attendance_type
    'VOD'
  end

  def converted_attendance_type
    'vod'
  end

  # AttendancesRecord 호환성 (student_id = user_name)
  def student_id
    user_name
  end

  # 클래스 메서드: 특정 학생의 최우선 레코드 조회
  def self.latest_for_student(content_tag_id, user_name)
    by_content_tag(content_tag_id)
      .by_user_name(user_name)
      .priority_ordered
      .first
  end

  # 클래스 메서드: 특정 학생의 히스토리 전체 조회
  def self.history_for_student(content_tag_id, user_name)
    by_content_tag(content_tag_id)
      .by_user_name(user_name)
      .order(created_at: :desc)
  end

  # 클래스 메서드: content_tag들의 모든 레코드 조회 (bulk)
  def self.for_content_tags(content_tag_ids)
    by_content_tags(content_tag_ids)
      .priority_ordered
  end
end
