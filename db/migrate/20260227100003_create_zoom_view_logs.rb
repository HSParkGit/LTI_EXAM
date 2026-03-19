# frozen_string_literal: true

#
# Zoom 참여 로그 테이블
# 외부 시스템에서 직접 INSERT하는 테이블 (스키마 변경 불가)
#
# 설계:
# - Canvas 원본과 동일한 스키마 유지
# - content_tag_id로 AttendanceSession과 연결
# - user_email이 학생 식별자
#
class CreateZoomViewLogs < ActiveRecord::Migration[7.1]
  def up
    create_table :zoom_view_logs, id: :integer, comment: 'Zoom 참여 로그 (외부 시스템 INSERT)' do |t|
      t.bigint :content_tag_id, null: false, comment: 'Canvas Content Tag ID'
      t.string :meeting_id, limit: 255, null: false, comment: 'Zoom Meeting ID'
      t.string :user_id, limit: 255, null: false, comment: 'Zoom User ID'
      t.string :user_name, limit: 255, null: false, comment: '사용자 이름'
      t.string :user_email, limit: 255, null: false, comment: '사용자 이메일'
      t.integer :duration, default: 0, null: false, comment: '참여 시간 (초)'
      t.string :join_time, limit: 30, null: false, comment: '참여 시작 시간'
      t.string :leave_time, limit: 30, null: false, comment: '참여 종료 시간'
      t.string :status, limit: 30, null: false, comment: '참여 상태'
      t.integer :viewer_rating, null: false, default: 0, comment: '참여율 (0-100)'
      t.timestamp :created_at, default: -> { 'now()' }, null: false, comment: '생성 시간'
    end

    # viewer_rating 범위 체크 (0-100)
    execute <<-SQL.squish
      ALTER TABLE zoom_view_logs
        ADD CONSTRAINT chk_zoom_view_logs_viewer_rating_range
        CHECK (viewer_rating >= 0 AND viewer_rating <= 100)
    SQL

    # UNIQUE 제약조건 (동일 참여 이벤트 중복 방지)
    add_index :zoom_view_logs,
              [:content_tag_id, :meeting_id, :user_email, :join_time, :leave_time],
              unique: true,
              name: 'uq_zoom_view_logs_content_meeting_user_time'

    # 조회 성능 인덱스
    add_index :zoom_view_logs, :content_tag_id, name: 'idx_zoom_view_logs_content_tag_id'
    add_index :zoom_view_logs, :meeting_id, name: 'idx_zoom_view_logs_meeting_id'
    add_index :zoom_view_logs, :user_email, name: 'idx_zoom_view_logs_user_email'
    add_index :zoom_view_logs, :join_time, name: 'idx_zoom_view_logs_join_time'
    add_index :zoom_view_logs, :leave_time, name: 'idx_zoom_view_logs_leave_time'
  end

  def down
    drop_table :zoom_view_logs, if_exists: true
  end
end
