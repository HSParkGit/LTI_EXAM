# frozen_string_literal: true

class AddCourseInfoToLtiContexts < ActiveRecord::Migration[7.1]
  def change
    add_column :lti_contexts, :context_label, :string, comment: "코스 코드 (예: HIC1006-13270)"
    add_column :lti_contexts, :instructor_names, :string, comment: "담당 교수명 (쉼표 구분)"
  end
end
