# frozen_string_literal: true

# LIVE(Zoom) 출결 설정 테이블
# Canvas의 ZoomSetting 참고
#
# 설계 방향:
# - 1:1 관계 (attendance_session:live_setting)
# - 참여 시간 기반 출결 인정
# - 출석/지각 임계값 설정
class CreateLiveSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :live_settings, comment: 'LIVE(Zoom) 출결 설정' do |t|
      t.references :attendance_session, null: false, foreign_key: true, index: { unique: true }, comment: '출결 세션 FK'
      t.string :meeting_id, comment: 'Zoom 미팅 ID'
      t.boolean :allow_attendance, default: true, comment: '출결 허용 여부'
      t.boolean :allow_tardiness, default: false, comment: '지각 허용 여부'
      t.integer :attendance_threshold, default: 80, comment: '출석 인정 % (참여 시간)'
      t.integer :tardiness_threshold, default: 50, comment: '지각 인정 %'
      t.datetime :start_time, comment: '시작 시간'
      t.integer :duration, comment: '진행 시간 (초)'
      t.timestamps
    end

  end
end
