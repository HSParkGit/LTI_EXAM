# frozen_string_literal: true

# 설계 방향 및 원칙:
# - LTI Context와 Canvas 코스를 매핑하는 테이블
# - 여러 Canvas 인스턴스에서 동일한 코스 ID가 있을 수 있으므로 platform_iss와 함께 관리
# - Canvas API 호출을 위한 canvas_url 저장
#
# 기술적 고려사항:
# - context_id와 platform_iss의 복합 유니크 인덱스
# - Canvas Open Source 지원 (canvas_url 분리)
#
# 사용 시 고려사항:
# - LTI Launch 시 자동 생성 또는 조회
# - Canvas API 호출 시 canvas_url 사용
class CreateLtiContexts < ActiveRecord::Migration[7.1]
  def change
    create_table :lti_contexts do |t|
      t.string :context_id, null: false, comment: 'LTI Context ID (Canvas 코스 ID)'
      t.string :context_type, null: false, default: 'Course', comment: 'Context 타입 (Course, Group 등)'
      t.string :context_title, comment: '코스 제목'
      t.string :platform_iss, null: false, comment: 'Canvas Platform ISS'
      t.string :canvas_url, null: false, comment: 'Canvas 인스턴스 URL (API 호출용)'
      t.string :deployment_id, comment: 'LTI Deployment ID'
      t.timestamps
    end
    
    add_index :lti_contexts, [:context_id, :platform_iss], unique: true, name: 'index_lti_contexts_on_context_id_and_platform_iss'
    add_index :lti_contexts, :platform_iss, name: 'index_lti_contexts_on_platform_iss'
  end
end

