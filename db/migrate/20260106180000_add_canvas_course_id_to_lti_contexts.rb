# frozen_string_literal: true

# 설계 방향 및 원칙:
# - LtiContext에 Canvas 실제 Course ID 저장
# - Custom Parameters에서 받은 canvas_course_id 저장
# - Canvas API 호출 시 사용
#
# 기술적 고려사항:
# - Custom Parameters에서 받은 값 또는 Canvas 특정 클레임에서 받은 값
# - null 허용 (기존 데이터 호환성)
#
# 사용 시 고려사항:
# - LTI Launch 시 자동 저장
# - ProjectBuilder에서 Canvas API 호출 시 사용
class AddCanvasCourseIdToLtiContexts < ActiveRecord::Migration[7.1]
  def change
    add_column :lti_contexts, :canvas_course_id, :integer, comment: 'Canvas 실제 Course ID (Custom Parameters 또는 Canvas 클레임에서 추출)'
  end
end

