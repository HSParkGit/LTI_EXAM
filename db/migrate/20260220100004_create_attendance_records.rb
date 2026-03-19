# frozen_string_literal: true

# 학생별 출결 기록 테이블
# Canvas의 PanoptoViewResult/ZoomViewResult 통합
#
# 설계 방향:
# - 학생별 출결 상태 저장
# - 외부 프로그램에서 시청 데이터 주입
# - 교수 강제 변경 이력 추적
#
# 출결 상태 코드:
# - 0: pending (미결)
# - 1: absent (결석)
# - 2: late (지각)
# - 3: excused (공결)
# - 4: present (출석)
class CreateAttendanceRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :attendance_records, comment: '학생별 출결 기록' do |t|
      t.references :attendance_session, null: false, foreign_key: true, comment: '출결 세션 FK'
      t.string :user_sub, null: false, comment: 'LTI user_sub (학생 식별자)'
      t.string :user_name, comment: '학생 이름 (캐시용)'
      t.integer :attendance_state, null: false, default: 0, comment: '0:미결 1:결석 2:지각 3:공결 4:출석'
      t.datetime :attended_at, comment: '출석 인정 시간'
      t.integer :view_duration, comment: '시청/참여 시간(초)'
      t.integer :view_percent, comment: '시청/참여율 (%)'
      t.boolean :teacher_forced_change, default: false, comment: '교수 강제 변경 여부'
      t.string :modified_by_user_sub, comment: '변경한 교수 user_sub'
      t.timestamps
    end

    add_index :attendance_records, [:attendance_session_id, :user_sub],
              unique: true, name: 'idx_attendance_records_unique'
    add_index :attendance_records, :user_sub
  end
end
