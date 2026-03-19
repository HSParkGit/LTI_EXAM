# frozen_string_literal: true

#
# Panopto 시청 로그 테이블
# 외부 시스템에서 직접 INSERT하는 테이블 (스키마 변경 불가)
#
# 설계:
# - Canvas 원본과 동일한 스키마 유지
# - content_tag_id로 AttendanceSession과 연결
# - user_name이 학생 식별자 (Canvas unique_id)
#
class CreatePanoptoViewLogs < ActiveRecord::Migration[7.1]
  def up
    create_table :panopto_view_logs, id: :bigint, comment: 'Panopto 시청 로그 (외부 시스템 INSERT)' do |t|
      t.bigint :content_tag_id, null: false, comment: 'Canvas Content Tag ID'
      t.uuid :session_id, null: false, comment: 'Panopto Session ID'
      t.uuid :user_id, null: false, comment: 'Panopto User ID (UUID)'
      t.string :user_name, limit: 50, null: false, comment: '사용자명 (Canvas unique_id)'
      t.string :event_time, null: false, comment: '이벤트 발생 시간'
      t.float :start_position, null: false, default: 0.0, comment: '시작 위치 (초)'
      t.float :seconds_viewed, null: false, default: 0.0, comment: '시청 시간 (초)'
      t.integer :viewer_rating, null: false, default: 0, comment: '시청 진도율 (0-100)'
      t.timestamp :created_at, default: -> { 'now()' }, null: false, comment: '생성 시간'
    end

    # PostgreSQL double precision 타입 변경
    execute "ALTER TABLE panopto_view_logs ALTER COLUMN start_position TYPE double precision"
    execute "ALTER TABLE panopto_view_logs ALTER COLUMN seconds_viewed TYPE double precision"

    # viewer_rating 범위 체크 (0-100)
    execute <<-SQL.squish
      ALTER TABLE panopto_view_logs
        ADD CONSTRAINT chk_panopto_view_logs_viewer_rating_range
        CHECK (viewer_rating >= 0 AND viewer_rating <= 100)
    SQL

    # UNIQUE 제약조건 (동일 시청 이벤트 중복 방지)
    add_index :panopto_view_logs,
              [:content_tag_id, :session_id, :user_id, :event_time],
              unique: true,
              name: 'uq_panopto_view_logs_content_session_user_time'

    # 조회 성능 인덱스
    add_index :panopto_view_logs, :content_tag_id, name: 'idx_panopto_view_logs_content_tag_id'
    add_index :panopto_view_logs, :session_id, name: 'idx_panopto_view_logs_session_id'
    add_index :panopto_view_logs, :user_id, name: 'idx_panopto_view_logs_user_id'
    add_index :panopto_view_logs, :user_name, name: 'idx_panopto_view_logs_user_name'
  end

  def down
    drop_table :panopto_view_logs, if_exists: true
  end
end
