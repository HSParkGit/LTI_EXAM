# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_01_06_180000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "lti_contexts", force: :cascade do |t|
    t.string "context_id", null: false, comment: "LTI Context ID (Canvas 코스 ID)"
    t.string "context_type", default: "Course", null: false, comment: "Context 타입 (Course, Group 등)"
    t.string "context_title", comment: "코스 제목"
    t.string "platform_iss", null: false, comment: "Canvas Platform ISS"
    t.string "canvas_url", null: false, comment: "Canvas 인스턴스 URL (API 호출용)"
    t.string "deployment_id", comment: "LTI Deployment ID"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "canvas_course_id", comment: "Canvas 실제 Course ID (Custom Parameters 또는 Canvas 클레임에서 추출)"
    t.index ["context_id", "platform_iss"], name: "index_lti_contexts_on_context_id_and_platform_iss", unique: true
    t.index ["platform_iss"], name: "index_lti_contexts_on_platform_iss"
  end

  create_table "lti_platforms", force: :cascade do |t|
    t.string "iss", null: false
    t.string "client_id", null: false
    t.string "name"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "canvas_url"
    t.string "client_secret", comment: "Canvas Developer Key의 Client Secret (암호화 저장)"
    t.string "canvas_api_token", comment: "Canvas Personal Access Token (암호화 저장)"
    t.index ["active"], name: "index_lti_platforms_on_active"
    t.index ["iss"], name: "index_lti_platforms_on_iss", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "lti_context_id", null: false, comment: "LTI Context 참조"
    t.string "name", null: false, comment: "프로젝트 이름"
    t.string "lti_user_sub", null: false, comment: "생성한 사용자의 LTI User Sub"
    t.text "assignment_ids", default: [], comment: "Canvas Assignment ID 배열", array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lti_context_id"], name: "index_projects_on_lti_context_id"
    t.index ["lti_user_sub"], name: "index_projects_on_lti_user_sub"
  end

  add_foreign_key "projects", "lti_contexts"
end
