# frozen_string_literal: true

# 같은 Week+Lesson에 여러 콘텐츠(ContentTag)가 매핑될 수 있으므로
# week+lesson_id unique 제약을 일반 인덱스로 변경
class RemoveWeekLessonUniqueIndex < ActiveRecord::Migration[7.1]
  def change
    remove_index :attendance_sessions, name: 'idx_attendance_sessions_unique'
    add_index :attendance_sessions, [:lti_context_id, :week, :lesson_id],
              name: 'idx_attendance_sessions_week_lesson',
              where: 'deleted_at IS NULL'
  end
end
