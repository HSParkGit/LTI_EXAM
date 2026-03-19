# frozen_string_literal: true

class AddAutoSyncColumns < ActiveRecord::Migration[7.1]
  def change
    # AttendanceSession soft delete
    add_column :attendance_sessions, :deleted_at, :datetime, comment: 'Soft delete timestamp'
    add_index :attendance_sessions, :deleted_at

    # LtiContext sync cache
    add_column :lti_contexts, :last_synced_at, :datetime, comment: 'Last attendance sync time'

    # 기존 unique index를 soft delete 호환으로 변경
    remove_index :attendance_sessions, name: :idx_attendance_sessions_unique
    add_index :attendance_sessions, [:lti_context_id, :week, :lesson_id],
              name: :idx_attendance_sessions_unique,
              unique: true,
              where: 'deleted_at IS NULL'

    remove_index :attendance_sessions, name: :idx_attendance_sessions_content_tag
    add_index :attendance_sessions, [:lti_context_id, :content_tag_id],
              name: :idx_attendance_sessions_content_tag,
              unique: true,
              where: 'content_tag_id IS NOT NULL AND deleted_at IS NULL'
  end
end
