# frozen_string_literal: true

#
# 출결 시청/참여 로그 조회 서비스
# Canvas 원본 ViewLogsService 포팅
#
# 핵심 기능:
# - Panopto 시청 로그: 30분 gap 기준 세션 그룹핑
# - Zoom 참여 로그: 개별 참여 이벤트
# - 강제 변경 이력 통합
# - 시간순 정렬 + 번호 매김
#
class AttendanceViewLogsService
  # Panopto 세션 그룹핑 gap (30분)
  SESSION_GAP_THRESHOLD = 30.minutes

  def initialize(session:, student_identifier:)
    @session = session
    @student_identifier = student_identifier
  end

  # @return [Hash] { success: true, records: [...], raw_records: [...] }
  def call
    return { success: false, error: 'Session or identifier missing' } unless @session&.content_tag_id && @student_identifier.present?

    view_logs = fetch_view_logs
    forced_changes = fetch_forced_changes

    all_records = merge_and_sort(view_logs, forced_changes)

    {
      success: true,
      records: format_records(group_panopto_sessions(all_records)),
      raw_records: format_records(all_records)
    }
  end

  private

  # 시청/참여 로그 조회
  def fetch_view_logs
    if @session.vod?
      PanoptoViewLog
        .by_content_tag(@session.content_tag_id)
        .by_user_name(@student_identifier)
        .order(event_time: :asc)
        .to_a
    else
      ZoomViewLog
        .by_content_tag(@session.content_tag_id)
        .by_user_email(@student_identifier)
        .order(join_time: :asc)
        .to_a
    end
  end

  # 강제 변경 이력 조회 (teacher_forced_change=1인 result 레코드)
  def fetch_forced_changes
    if @session.vod?
      PanoptoViewResult
        .where(content_tag_id: @session.content_tag_id, user_name: @student_identifier, teacher_forced_change: 1)
        .order(updated_at: :asc)
        .to_a
    else
      ZoomViewResult
        .where(content_tag_id: @session.content_tag_id, user_email: @student_identifier, teacher_forced_change: 1)
        .order(updated_at: :asc)
        .to_a
    end
  end

  # 시청 로그 + 강제 변경 이력 통합 정렬
  def merge_and_sort(view_logs, forced_changes)
    all = []

    view_logs.each do |log|
      all << { type: :view_log, record: log, sort_time: sort_time_for_log(log) }
    end

    forced_changes.each do |change|
      all << { type: :forced_change, record: change, sort_time: change.updated_at }
    end

    all.sort_by { |r| r[:sort_time] || Time.at(0) }.reverse
  end

  def sort_time_for_log(log)
    if log.is_a?(PanoptoViewLog)
      log.event_time_parsed || Time.at(0)
    else
      log.join_time_parsed || Time.at(0)
    end
  end

  # Panopto 시청 로그를 세션 단위로 그룹핑 (30분 gap)
  def group_panopto_sessions(all_records)
    panopto_logs = all_records.select { |r| r[:type] == :view_log && r[:record].is_a?(PanoptoViewLog) }
    other_records = all_records.reject { |r| r[:type] == :view_log && r[:record].is_a?(PanoptoViewLog) }

    return all_records if panopto_logs.empty?

    # 시간순 정렬 (오래된 순)
    sorted = panopto_logs.sort_by { |r| r[:sort_time] || Time.at(0) }

    sessions = []
    current_session = [sorted.first]

    sorted.drop(1).each do |record|
      prev_time = current_session.last[:sort_time]
      curr_time = record[:sort_time]

      if prev_time && curr_time && (curr_time - prev_time) > SESSION_GAP_THRESHOLD
        sessions << current_session
        current_session = [record]
      else
        current_session << record
      end
    end
    sessions << current_session

    # 각 세션을 하나의 요약 레코드로 변환
    grouped = sessions.map do |session_logs|
      logs = session_logs.map { |r| r[:record] }
      total_seconds = logs.sum(&:seconds_viewed)
      last_rating = logs.last.viewer_rating

      {
        type: :panopto_session,
        first_log: logs.first,
        last_log: logs.last,
        total_seconds: total_seconds,
        session_rate: last_rating,
        sort_time: logs.last.event_time_parsed || Time.at(0)
      }
    end

    (grouped + other_records).sort_by { |r| r[:sort_time] || Time.at(0) }.reverse
  end

  # 레코드 포맷팅
  def format_records(records)
    total = records.size
    records.map.with_index do |record_data, index|
      number = total - index # 오래된 데이터가 1번
      case record_data[:type]
      when :view_log
        format_view_log(record_data[:record], number)
      when :panopto_session
        format_panopto_session(record_data, number)
      when :forced_change
        format_forced_change(record_data[:record], number)
      end
    end.compact
  end

  # 개별 시청 로그 포맷팅 (Zoom용, 또는 raw_records용 Panopto)
  def format_view_log(log, number)
    if log.is_a?(PanoptoViewLog)
      event_time = log.event_time_parsed
      {
        number: number,
        date: event_time&.strftime('%Y-%m-%d') || '-',
        time: log.view_time_range_string,
        view_rate: "#{log.viewer_rating}%",
        notes: '-'
      }
    else
      # ZoomViewLog
      join_time = log.join_time_parsed
      total_sec = log.duration.to_i
      time_str = format_duration(total_sec)
      {
        number: number,
        date: join_time&.strftime('%Y-%m-%d') || '-',
        time: log.view_time_range_string,
        view_rate: "#{log.viewer_rating}% (#{time_str})",
        notes: '-'
      }
    end
  end

  # Panopto 세션 요약 포맷팅
  def format_panopto_session(session_data, number)
    first_log = session_data[:first_log]
    last_log = session_data[:last_log]

    first_time = first_log.event_time_parsed
    last_time = last_log.event_time_parsed

    start_str = first_time&.strftime('%I:%M %p') || '-'
    end_str = last_time&.strftime('%I:%M %p') || '-'

    total_sec = session_data[:total_seconds].to_i
    time_str = format_duration(total_sec)
    rate = session_data[:session_rate]
    rate_str = rate ? "#{rate}% (#{time_str})" : '-'

    {
      number: number,
      date: first_time&.strftime('%Y-%m-%d') || '-',
      time: "#{start_str} - #{end_str}",
      view_rate: rate_str,
      notes: '-'
    }
  end

  # 강제 변경 이력 포맷팅
  def format_forced_change(change, number)
    updated_at = change.updated_at&.in_time_zone('Asia/Seoul')
    state_text = change.attendance_state_text

    {
      number: number,
      date: updated_at&.strftime('%Y-%m-%d') || '-',
      time: updated_at&.strftime('%I:%M %p') || '-',
      view_rate: '-',
      notes: "#{state_text} - 출결 상태 변경"
    }
  end

  def format_duration(seconds)
    minutes = seconds / 60
    secs = seconds % 60
    if minutes > 0
      "#{minutes}분 #{secs}초"
    else
      "#{secs}초"
    end
  end
end
