# frozen_string_literal: true

module AttendanceHelper
  # 출결 상태 상수 (PanoptoViewResult/ZoomViewResult와 동일)
  STATE_PENDING = 0
  STATE_ABSENT = 1
  STATE_LATE = 2
  STATE_EXCUSED = 3
  STATE_PRESENT = 4

  STATE_LABELS = {
    STATE_PENDING => '미결',
    STATE_ABSENT => '결석',
    STATE_LATE => '지각',
    STATE_EXCUSED => '공결',
    STATE_PRESENT => '출석'
  }.freeze

  STATE_CSS_CLASSES = {
    STATE_PENDING => 'state-pending',
    STATE_ABSENT => 'state-absent',
    STATE_LATE => 'state-late',
    STATE_EXCUSED => 'state-excused',
    STATE_PRESENT => 'state-present'
  }.freeze

  # 출결 상태 라벨 (숫자 → 문자열)
  def attendance_state_label(state)
    STATE_LABELS[state.to_i] || '알 수 없음'
  end

  # 출결 상태 라벨 (문자열 → 한글)
  def attendance_status_label(status)
    case status.to_s
    when 'present' then '출석'
    when 'excused' then '공결'
    when 'late' then '지각'
    when 'absent' then '결석'
    else '미결'
    end
  end

  # 출결 상태 CSS 클래스
  def attendance_state_class(state)
    STATE_CSS_CLASSES[state.to_i] || ''
  end

  # 출결 상태 CSS 클래스 (문자열 버전)
  def attendance_status_class(status)
    case status.to_s
    when 'present' then 'state-present'
    when 'excused' then 'state-excused'
    when 'late' then 'state-late'
    when 'absent' then 'state-absent'
    else 'state-pending'
    end
  end

  # 출결 상태 배지 HTML
  def attendance_state_badge(state)
    label = attendance_state_label(state)
    css_class = attendance_state_class(state)
    content_tag(:span, label, class: "badge #{css_class}")
  end

  # 출결 상태 배지 (문자열 버전)
  def attendance_status_badge(status)
    label = attendance_status_label(status)
    css_class = attendance_status_class(status)
    content_tag(:span, label, class: "badge #{css_class}")
  end

  # 출결 통계 요약 문자열
  def attendance_stats_summary(stats)
    parts = []
    parts << "출석 #{stats[:present]}" if stats[:present].to_i > 0
    parts << "지각 #{stats[:late]}" if stats[:late].to_i > 0
    parts << "결석 #{stats[:absent]}" if stats[:absent].to_i > 0
    parts << "공결 #{stats[:excused]}" if stats[:excused].to_i > 0
    parts << "미결 #{stats[:pending]}" if stats[:pending].to_i > 0
    parts.join(' / ')
  end

  # 출결 타입 라벨
  def attendance_type_label(type)
    case type.to_s.downcase
    when 'vod' then 'VOD'
    when 'live' then 'LIVE'
    else type.to_s.upcase
    end
  end

  # 출결 타입 배지
  def attendance_type_badge(type)
    label = attendance_type_label(type)
    css_class = type.to_s.downcase == 'live' ? 'badge-live' : 'badge-vod'
    content_tag(:span, label, class: "badge #{css_class}")
  end

  # 상태 아이콘 (매트릭스 셀용)
  def status_icon(status)
    case status.to_s
    when 'present' then '●'
    when 'excused' then '●'
    when 'late' then '▲'
    when 'absent' then '✕'
    else '—'
    end
  end

  # 시간 포맷팅 (KST)
  def format_attendance_time(time)
    return '-' if time.blank?
    time.in_time_zone('Asia/Seoul').strftime('%Y-%m-%d %H:%M')
  end

  # 진도율 포맷팅
  def format_percent(percent)
    return '-' if percent.blank?
    "#{percent}%"
  end

  # 시청 시간 포맷팅 (분:초)
  def format_duration(seconds)
    return '-' if seconds.blank?
    minutes = seconds / 60
    secs = seconds % 60
    format('%d:%02d', minutes, secs)
  end
end
