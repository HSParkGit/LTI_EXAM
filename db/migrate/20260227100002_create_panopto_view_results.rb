# frozen_string_literal: true

#
# Panopto 출결 결과 테이블
# 외부 시스템에서 직접 INSERT하는 테이블 (스키마 변경 불가)
#
# 설계:
# - Canvas 원본과 동일한 스키마 유지
# - content_tag_id로 AttendanceSession과 연결
# - user_name이 학생 식별자 (Canvas unique_id)
# - attendance_state: 0=미결, 1=결석, 2=지각, 3=공결, 4=출석
#
class CreatePanoptoViewResults < ActiveRecord::Migration[7.1]
  def up
    create_table :panopto_view_results, id: :bigint, comment: 'Panopto 출결 결과 (외부 시스템 INSERT)' do |t|
      t.bigint :content_tag_id, null: false, comment: 'Canvas Content Tag ID'
      t.uuid :session_id, null: false, comment: 'Panopto Session ID'
      t.uuid :user_id, null: false, comment: 'Panopto User ID (UUID)'
      t.string :user_name, limit: 50, null: false, comment: '사용자명 (Canvas unique_id)'
      t.integer :attendance_state, default: 0, null: false, comment: '출결 상태 (0:미결, 1:결석, 2:지각, 3:공결, 4:출석)'
      t.integer :teacher_forced_change, default: 0, null: false, comment: '교수 강제 변경 (0:자동, 1:수동)'
      t.bigint :modified_by_user_id, default: 0, null: false, comment: '변경한 교수 ID'
      t.timestamp :created_at, default: -> { 'now()' }, null: false, comment: '생성 시간'
      t.timestamp :updated_at, default: -> { 'now()' }, null: false, comment: '수정 시간'
    end

    # attendance_state 범위 체크 (0-4)
    execute <<-SQL.squish
      ALTER TABLE panopto_view_results
        ADD CONSTRAINT chk_panopto_view_results_attendance_state
        CHECK (attendance_state >= 0 AND attendance_state <= 4)
    SQL

    # UNIQUE 제약조건 (학생당 하나의 출결 결과)
    add_index :panopto_view_results,
              [:content_tag_id, :user_id],
              unique: true,
              name: 'uq_panopto_view_results_content_user'

    # 조회 성능 인덱스
    add_index :panopto_view_results, :content_tag_id, name: 'idx_panopto_view_results_content_tag_id'
    add_index :panopto_view_results, :session_id, name: 'idx_panopto_view_results_session_id'
    add_index :panopto_view_results, :user_id, name: 'idx_panopto_view_results_user_id'
    add_index :panopto_view_results, :user_name, name: 'idx_panopto_view_results_user_name'

    # 교수 강제 변경 우선 조회용 복합 인덱스
    add_index :panopto_view_results,
              [:content_tag_id, :user_name, :teacher_forced_change, :created_at],
              name: 'idx_panopto_view_results_priority'
  end

  def down
    drop_table :panopto_view_results, if_exists: true
  end
end
