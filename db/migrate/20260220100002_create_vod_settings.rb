# frozen_string_literal: true

# VOD(Panopto) 출결 설정 테이블
# Canvas의 PanoptoSetting 참고
#
# 설계 방향:
# - 1:1 관계 (attendance_session:vod_setting)
# - 진도율 기반 출결 인정
# - 출석/지각 기간 분리 관리
class CreateVodSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :vod_settings, comment: 'VOD(Panopto) 출결 설정' do |t|
      t.references :attendance_session, null: false, foreign_key: true, index: { unique: true }, comment: '출결 세션 FK'
      t.string :session_id, comment: 'Panopto 세션 ID'
      t.boolean :allow_attendance, default: true, comment: '출결 허용 여부'
      t.boolean :allow_tardiness, default: false, comment: '지각 허용 여부'
      t.integer :percent_required, default: 80, comment: '필요 진도율 (0-100)'
      t.datetime :unlock_at, comment: '열람 시작'
      t.datetime :lock_at, comment: '열람 종료'
      t.datetime :attendance_finish_at, comment: '출석 마감'
      t.datetime :tardiness_finish_at, comment: '지각 마감'
      t.timestamps
    end

  end
end
