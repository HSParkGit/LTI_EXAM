# frozen_string_literal: true

#
# 기존 attendance_records 테이블 삭제
#
# 이유:
# - 외부 시스템이 panopto_view_results/zoom_view_results에 직접 INSERT
# - user_sub 기반 설계가 외부 시스템 식별자(unique_id/email)와 불일치
# - Canvas 원본 구조와 맞추기 위해 삭제
#
class DropAttendanceRecords < ActiveRecord::Migration[7.1]
  def up
    # 외래키 제거 후 테이블 삭제
    remove_foreign_key :attendance_records, :attendance_sessions, if_exists: true
    drop_table :attendance_records, if_exists: true
  end

  def down
    # 롤백 시 테이블 재생성
    create_table :attendance_records, comment: '학생별 출결 기록' do |t|
      t.bigint :attendance_session_id, null: false, comment: '출결 세션 FK'
      t.string :user_sub, null: false, comment: 'LTI user_sub (학생 식별자)'
      t.string :user_name, comment: '학생 이름 (캐시용)'
      t.integer :attendance_state, default: 0, null: false, comment: '0:미결 1:결석 2:지각 3:공결 4:출석'
      t.datetime :attended_at, comment: '출석 인정 시간'
      t.integer :view_duration, comment: '시청/참여 시간(초)'
      t.integer :view_percent, comment: '시청/참여율 (%)'
      t.boolean :teacher_forced_change, default: false, comment: '교수 강제 변경 여부'
      t.string :modified_by_user_sub, comment: '변경한 교수 user_sub'
      t.timestamps
    end

    add_index :attendance_records, :attendance_session_id
    add_index :attendance_records, :user_sub
    add_index :attendance_records, [:attendance_session_id, :user_sub], unique: true, name: 'idx_attendance_records_unique'
    add_foreign_key :attendance_records, :attendance_sessions
  end
end
