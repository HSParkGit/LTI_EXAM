class CreateLtiPlatforms < ActiveRecord::Migration[7.1]
  def change
    create_table :lti_platforms do |t|
      t.string :iss, null: false
      t.string :client_id, null: false
      t.string :name
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    add_index :lti_platforms, :iss, unique: true
    add_index :lti_platforms, :active
  end
end
