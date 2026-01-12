class ChangeLtiPlatformsIssIndexToComposite < ActiveRecord::Migration[7.1]
  def change
    # 기존 iss 단일 unique 인덱스 제거
    remove_index :lti_platforms, :iss, if_exists: true
    
    # [iss, client_id] 조합에 unique 인덱스 추가
    # 같은 Canvas 인스턴스(iss)에서 여러 Developer Key를 사용할 수 있도록
    add_index :lti_platforms, [:iss, :client_id], unique: true, name: 'index_lti_platforms_on_iss_and_client_id'
    
    # iss로 조회를 위한 일반 인덱스도 추가 (unique 아님)
    add_index :lti_platforms, :iss, name: 'index_lti_platforms_on_iss'
  end
end
