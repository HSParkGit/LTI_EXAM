class AddCanvasUrlToLtiPlatforms < ActiveRecord::Migration[7.1]
  def change
    add_column :lti_platforms, :canvas_url, :string
    # canvas_url은 선택사항 (기존 데이터 호환성을 위해 null 허용)
    # Canvas Open Source의 경우 실제 인스턴스 URL을 저장
    # 예: https://5e60aecc33bb.ngrok-free.app
  end
end
