# frozen_string_literal: true

# 설계 방향 및 원칙:
# - Project 테이블 생성 (LTI Tool 자체 DB)
# - Canvas Assignment는 ID 배열로만 참조 (Canvas API로 관리)
# - Canvas 의존성 제거 (context, assignments 관계 제거)
#
# 기술적 고려사항:
# - assignment_ids는 PostgreSQL 배열 타입 사용
# - LTI User Sub로 사용자 식별 (Canvas User ID 불필요)
#
# 사용 시 고려사항:
# - Assignment 데이터는 Canvas DB에 저장
# - Project는 Assignment ID만 참조
class CreateProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :projects do |t|
      t.references :lti_context, null: false, foreign_key: true, comment: 'LTI Context 참조'
      t.string :name, null: false, comment: '프로젝트 이름'
      t.string :lti_user_sub, null: false, comment: '생성한 사용자의 LTI User Sub'
      t.text :assignment_ids, array: true, default: [], comment: 'Canvas Assignment ID 배열'
      t.timestamps
    end
    
    # t.references가 자동으로 인덱스를 생성하므로 별도 추가 불필요
    add_index :projects, :lti_user_sub, name: 'index_projects_on_lti_user_sub'
  end
end

