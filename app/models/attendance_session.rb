# frozen_string_literal: true

# 출결 세션 모델
# Canvas의 ContentTag 역할 - 강의 세션 기본 정보
#
# 설계 방향:
# - 주차/차시 기반 세션 관리 (Week 1-Lesson 1 형태)
# - Canvas content_tag_id로 External Tool과 매핑
# - VOD/LIVE 타입에 따라 각각의 설정 모델과 1:1 관계
# - 외부 시스템이 INSERT한 데이터는 content_tag_id로 연결
#
# 관계:
# - belongs_to: lti_context
# - has_one: vod_setting (VOD 타입인 경우)
# - has_one: live_setting (LIVE 타입인 경우)
# - 외부 데이터: panopto_view_results / zoom_view_results (content_tag_id로 JOIN)
class AttendanceSession < ApplicationRecord
  belongs_to :lti_context
  has_one :vod_setting, dependent: :destroy
  has_one :live_setting, dependent: :destroy

  accepts_nested_attributes_for :vod_setting, :live_setting,
                                allow_destroy: true,
                                reject_if: :all_blank

  # 출결 타입 상수
  ATTENDANCE_TYPE_VOD = 'vod'
  ATTENDANCE_TYPE_LIVE = 'live'
  ATTENDANCE_TYPES = [ATTENDANCE_TYPE_VOD, ATTENDANCE_TYPE_LIVE].freeze

  validates :week, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :lesson_id, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :attendance_type, presence: true, inclusion: { in: ATTENDANCE_TYPES }
  # 같은 week+lesson_id에 여러 콘텐츠(ContentTag)가 매핑될 수 있음
  # (예: 같은 차시에 Panopto 영상 2개 + Zoom 수업 1개)

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # 스코프
  scope :by_week, ->(week) { where(week: week) }
  scope :ordered, -> { order(week: :asc, lesson_id: :asc) }
  scope :vod_sessions, -> { where(attendance_type: ATTENDANCE_TYPE_VOD) }
  scope :live_sessions, -> { where(attendance_type: ATTENDANCE_TYPE_LIVE) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  def active?
    deleted_at.nil?
  end

  # VOD 타입 여부
  def vod?
    attendance_type == ATTENDANCE_TYPE_VOD
  end

  # LIVE 타입 여부
  def live?
    attendance_type == ATTENDANCE_TYPE_LIVE
  end

  # 현재 타입에 맞는 설정 객체 반환
  def setting
    vod? ? vod_setting : live_setting
  end

  # 주차-차시 표시 문자열
  def week_lesson_label
    "#{week}주차 #{lesson_id}차시"
  end

  # 전체 제목 (주차-차시 + 제목)
  def full_title
    title.present? ? "#{week_lesson_label} - #{title}" : week_lesson_label
  end

  # ========================================
  # 외부 시스템 데이터 조회 메서드
  # content_tag_id로 panopto/zoom_view_results 테이블 조회
  # ========================================

  # 이 세션의 모든 출결 결과 조회
  def view_results
    return [] unless content_tag_id.present?

    if vod?
      PanoptoViewResult.by_content_tag(content_tag_id).priority_ordered
    else
      ZoomViewResult.by_content_tag(content_tag_id).priority_ordered
    end
  end

  # 특정 학생의 출결 결과 조회
  # @param identifier [String] Panopto: user_name(unique_id), Zoom: user_email
  def find_student_result(identifier)
    return nil unless content_tag_id.present? && identifier.present?

    if vod?
      PanoptoViewResult.latest_for_student(content_tag_id, identifier)
    else
      ZoomViewResult.latest_for_student(content_tag_id, identifier)
    end
  end

  # 특정 학생의 시청/참여 로그 조회
  # @param identifier [String] Panopto: user_name(unique_id), Zoom: user_email
  def find_student_logs(identifier)
    return [] unless content_tag_id.present? && identifier.present?

    if vod?
      PanoptoViewLog.for_student(content_tag_id, identifier)
    else
      ZoomViewLog.for_student(content_tag_id, identifier)
    end
  end

  # content_tag_id 매핑 여부
  def mapped?
    content_tag_id.present?
  end
end
