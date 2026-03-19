# frozen_string_literal: true

#
# 출결 통계 계산 서비스
# Canvas 원본 StatsCalculator 포팅
#
# 핵심 기능:
# - 기간 기반 자동 출결 판정 (resolve_pending_status)
# - 출결 상태 변환 (attendance_state → 문자열)
# - 통계 계산 (기록 없는 학생 포함)
# - 출석률 계산
#
class AttendanceStatsCalculator
  class << self
    # ========================================
    # 출결 상태 변환
    # ========================================

    # attendance_state를 문자열로 변환
    # pending인 경우 기간 체크 후 자동 판정
    #
    # @param state [Integer] 출결 상태 코드 (0-4)
    # @param session [AttendanceSession] 세션 (기간 체크용)
    # @return [String] 'present', 'excused', 'late', 'absent', 'pending'
    def convert_state_to_string(state, session: nil)
      case state
      when PanoptoViewResult::ATTENDANCE_STATE_PRESENT then 'present'
      when PanoptoViewResult::ATTENDANCE_STATE_EXCUSED then 'excused'
      when PanoptoViewResult::ATTENDANCE_STATE_LATE then 'late'
      when PanoptoViewResult::ATTENDANCE_STATE_ABSENT then 'absent'
      else
        resolve_pending_status(session)
      end
    end

    # 기간 기반 자동 출결 판정
    # 출결 기록이 없거나 pending 상태일 때 기간으로 판정
    #
    # @param session [AttendanceSession] 세션
    # @return [String] 'present', 'late', 'absent', 'pending'
    def resolve_pending_status(session)
      return 'pending' unless session&.setting&.allow_attendance?

      now = Time.current

      if session.vod?
        resolve_vod_pending(session.vod_setting, now)
      else
        resolve_live_pending(session.live_setting, now)
      end
    end

    # ========================================
    # 통계 계산
    # ========================================

    # 세션의 출결 통계 계산
    # 기록 없는 학생도 포함 (마감 후면 absent로 카운트)
    #
    # @param session [AttendanceSession] 세션
    # @param records [Array] 출결 레코드 배열
    # @param total_students [Integer] 전체 학생 수
    # @return [Hash] { present: N, excused: N, late: N, absent: N, pending: N }
    def calculate_stats(session, records, total_students)
      stats = { present: 0, excused: 0, late: 0, absent: 0, pending: 0 }
      students_with_records = Set.new
      pending_count = 0

      records.each do |record|
        next unless record.student_id.present?

        students_with_records << record.student_id

        case convert_state_to_string(record.attendance_state, session: session)
        when 'present' then stats[:present] += 1
        when 'excused' then stats[:excused] += 1
        when 'late' then stats[:late] += 1
        when 'absent' then stats[:absent] += 1
        else pending_count += 1
        end
      end

      # 기록 없는 학생 처리
      no_record_count = total_students - students_with_records.count
      no_record_status = resolve_pending_status(session)
      case no_record_status
      when 'absent' then stats[:absent] += no_record_count
      when 'late' then stats[:late] += no_record_count
      else pending_count += no_record_count
      end
      stats[:pending] = pending_count

      stats
    end

    # 출석률 계산
    # (출석 + 공결) / 전체 학생 * 100
    #
    # @param stats [Hash] 통계 해시
    # @param total_students [Integer] 전체 학생 수
    # @return [Float] 출석률 (0.0 ~ 100.0)
    def calculate_attendance_rate(stats, total_students)
      return 0.0 if total_students.zero?

      ((stats[:present] + stats[:excused]).to_f / total_students * 100).round(2)
    end

    # ========================================
    # 우선순위 상태 결정
    # ========================================

    # 여러 상태 중 우선순위가 높은 것 선택
    # absent > late > present/excused > pending
    #
    # @param statuses [Array<String>] 상태 배열
    # @return [String] 우선순위가 가장 높은 상태
    def determine_priority_status(statuses)
      return 'pending' if statuses.blank?
      return 'absent' if statuses.include?('absent')
      return 'late' if statuses.include?('late')
      return 'present' if statuses.include?('present') || statuses.include?('excused')

      'pending'
    end

    # ========================================
    # 출결 타입 판정
    # ========================================

    def determine_attendance_type(session)
      return '-' unless session
      session.vod? ? 'VOD' : 'LIVE'
    end

    # ========================================
    # 수업 시간 / 마감일 포맷팅
    # ========================================

    def format_class_time(session)
      return '-' unless session&.setting

      if session.live?
        setting = session.live_setting
        return '-' unless setting&.start_time && setting&.duration

        end_time = setting.start_time + setting.duration.seconds
        format_time_range(setting.start_time, end_time)
      else
        setting = session.vod_setting
        return '-' unless setting&.unlock_at && setting&.attendance_finish_at

        format_time_range(setting.unlock_at, setting.attendance_finish_at)
      end
    end

    def format_due(session)
      return '-' unless session&.vod? && session.vod_setting&.lock_at.present?

      format_datetime(session.vod_setting.lock_at)
    end

    private

    # VOD pending 판정
    def resolve_vod_pending(setting, now)
      return 'pending' unless setting&.allow_attendance?

      attendance_finish = setting.attendance_finish_at
      return 'pending' unless attendance_finish && now >= attendance_finish

      if setting.allow_tardiness? && setting.tardiness_finish_at.present?
        now >= setting.tardiness_finish_at ? 'absent' : 'late'
      else
        'absent'
      end
    end

    # LIVE pending 판정
    def resolve_live_pending(setting, now)
      return 'pending' unless setting&.allow_attendance?
      return 'pending' unless setting&.start_time && setting&.duration

      end_time = setting.start_time + setting.duration.seconds
      now >= end_time ? 'absent' : 'pending'
    end

    def format_time_range(start_time, end_time)
      "#{format_datetime(start_time)} ~ #{format_datetime(end_time)}"
    end

    def format_datetime(datetime)
      return '-' unless datetime

      datetime.strftime('%m/%d %H:%M')
    end
  end
end
