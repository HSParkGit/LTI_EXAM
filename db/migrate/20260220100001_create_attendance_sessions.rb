# frozen_string_literal: true

# 출결 세션 (강의) 테이블 생성
# Canvas의 ContentTag 역할 - 강의 세션 기본 정보 저장
#
# 설계 방향:
# - 주차/차시 기반 세션 관리
# - Canvas content_tag_id로 매핑 (Panopto/Zoom External Tool)
# - VOD/LIVE 유형 구분
class CreateAttendanceSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :attendance_sessions, comment: '출결 세션 (강의)' do |t|
      t.references :lti_context, null: false, foreign_key: true, comment: 'LTI Context FK'
      t.bigint :content_tag_id, comment: 'Canvas content_tag ID (매핑용)'
      t.integer :week, null: false, comment: '주차 (1, 2, 3...)'
      t.integer :lesson_id, null: false, comment: '차시 (1, 2, 3...)'
      t.string :title, comment: '강의 제목'
      t.string :attendance_type, null: false, default: 'vod', comment: 'vod 또는 live'
      t.timestamps
    end

    add_index :attendance_sessions, [:lti_context_id, :week, :lesson_id],
              unique: true, name: 'idx_attendance_sessions_unique'
    add_index :attendance_sessions, [:lti_context_id, :content_tag_id],
              unique: true, name: 'idx_attendance_sessions_content_tag',
              where: 'content_tag_id IS NOT NULL'
  end
end
