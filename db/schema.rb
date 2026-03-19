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

ActiveRecord::Schema[7.1].define(version: 2026_03_19_200001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "attendance_sessions", comment: "출결 세션 (강의)", force: :cascade do |t|
    t.bigint "lti_context_id", null: false, comment: "LTI Context FK"
    t.bigint "content_tag_id", comment: "Canvas content_tag ID (매핑용)"
    t.integer "week", null: false, comment: "주차 (1, 2, 3...)"
    t.integer "lesson_id", null: false, comment: "차시 (1, 2, 3...)"
    t.string "title", comment: "강의 제목"
    t.string "attendance_type", default: "vod", null: false, comment: "vod 또는 live"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at", comment: "Soft delete timestamp"
    t.index ["deleted_at"], name: "index_attendance_sessions_on_deleted_at"
    t.index ["lti_context_id", "content_tag_id"], name: "idx_attendance_sessions_content_tag", unique: true, where: "((content_tag_id IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["lti_context_id", "week", "lesson_id"], name: "idx_attendance_sessions_week_lesson", where: "(deleted_at IS NULL)"
    t.index ["lti_context_id"], name: "index_attendance_sessions_on_lti_context_id"
  end

  create_table "live_settings", comment: "LIVE(Zoom) 출결 설정", force: :cascade do |t|
    t.bigint "attendance_session_id", null: false, comment: "출결 세션 FK"
    t.string "meeting_id", comment: "Zoom 미팅 ID"
    t.boolean "allow_attendance", default: true, comment: "출결 허용 여부"
    t.boolean "allow_tardiness", default: false, comment: "지각 허용 여부"
    t.integer "attendance_threshold", default: 80, comment: "출석 인정 % (참여 시간)"
    t.integer "tardiness_threshold", default: 50, comment: "지각 인정 %"
    t.datetime "start_time", comment: "시작 시간"
    t.integer "duration", comment: "진행 시간 (초)"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attendance_session_id"], name: "index_live_settings_on_attendance_session_id", unique: true
  end

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
    t.string "context_label", comment: "코스 코드 (예: HIC1006-13270)"
    t.string "instructor_names", comment: "담당 교수명 (쉼표 구분)"
    t.datetime "last_synced_at", comment: "Last attendance sync time"
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
    t.index ["iss", "client_id"], name: "index_lti_platforms_on_iss_and_client_id", unique: true
    t.index ["iss"], name: "index_lti_platforms_on_iss"
  end

  create_table "panopto_view_logs", comment: "Panopto 시청 로그 (외부 시스템 INSERT)", force: :cascade do |t|
    t.bigint "content_tag_id", null: false, comment: "Canvas Content Tag ID"
    t.uuid "session_id", null: false, comment: "Panopto Session ID"
    t.uuid "user_id", null: false, comment: "Panopto User ID (UUID)"
    t.string "user_name", limit: 50, null: false, comment: "사용자명 (Canvas unique_id)"
    t.string "event_time", null: false, comment: "이벤트 발생 시간"
    t.float "start_position", default: 0.0, null: false, comment: "시작 위치 (초)"
    t.float "seconds_viewed", default: 0.0, null: false, comment: "시청 시간 (초)"
    t.integer "viewer_rating", default: 0, null: false, comment: "시청 진도율 (0-100)"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false, comment: "생성 시간"
    t.index ["content_tag_id", "session_id", "user_id", "event_time"], name: "uq_panopto_view_logs_content_session_user_time", unique: true
    t.index ["content_tag_id"], name: "idx_panopto_view_logs_content_tag_id"
    t.index ["session_id"], name: "idx_panopto_view_logs_session_id"
    t.index ["user_id"], name: "idx_panopto_view_logs_user_id"
    t.index ["user_name"], name: "idx_panopto_view_logs_user_name"
    t.check_constraint "viewer_rating >= 0 AND viewer_rating <= 100", name: "chk_panopto_view_logs_viewer_rating_range"
  end

  create_table "panopto_view_results", comment: "Panopto 출결 결과 (외부 시스템 INSERT)", force: :cascade do |t|
    t.bigint "content_tag_id", null: false, comment: "Canvas Content Tag ID"
    t.uuid "session_id", null: false, comment: "Panopto Session ID"
    t.uuid "user_id", null: false, comment: "Panopto User ID (UUID)"
    t.string "user_name", limit: 50, null: false, comment: "사용자명 (Canvas unique_id)"
    t.integer "attendance_state", default: 0, null: false, comment: "출결 상태 (0:미결, 1:결석, 2:지각, 3:공결, 4:출석)"
    t.integer "teacher_forced_change", default: 0, null: false, comment: "교수 강제 변경 (0:자동, 1:수동)"
    t.bigint "modified_by_user_id", default: 0, null: false, comment: "변경한 교수 ID"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false, comment: "생성 시간"
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false, comment: "수정 시간"
    t.index ["content_tag_id", "user_id"], name: "uq_panopto_view_results_content_user", unique: true
    t.index ["content_tag_id", "user_name", "teacher_forced_change", "created_at"], name: "idx_panopto_view_results_priority"
    t.index ["content_tag_id"], name: "idx_panopto_view_results_content_tag_id"
    t.index ["session_id"], name: "idx_panopto_view_results_session_id"
    t.index ["user_id"], name: "idx_panopto_view_results_user_id"
    t.index ["user_name"], name: "idx_panopto_view_results_user_name"
    t.check_constraint "attendance_state >= 0 AND attendance_state <= 4", name: "chk_panopto_view_results_attendance_state"
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

  create_table "vod_settings", comment: "VOD(Panopto) 출결 설정", force: :cascade do |t|
    t.bigint "attendance_session_id", null: false, comment: "출결 세션 FK"
    t.string "session_id", comment: "Panopto 세션 ID"
    t.boolean "allow_attendance", default: true, comment: "출결 허용 여부"
    t.boolean "allow_tardiness", default: false, comment: "지각 허용 여부"
    t.integer "percent_required", default: 80, comment: "필요 진도율 (0-100)"
    t.datetime "unlock_at", comment: "열람 시작"
    t.datetime "lock_at", comment: "열람 종료"
    t.datetime "attendance_finish_at", comment: "출석 마감"
    t.datetime "tardiness_finish_at", comment: "지각 마감"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attendance_session_id"], name: "index_vod_settings_on_attendance_session_id", unique: true
  end

  create_table "zoom_view_logs", id: :serial, comment: "Zoom 참여 로그 (외부 시스템 INSERT)", force: :cascade do |t|
    t.bigint "content_tag_id", null: false, comment: "Canvas Content Tag ID"
    t.string "meeting_id", limit: 255, null: false, comment: "Zoom Meeting ID"
    t.string "user_id", limit: 255, null: false, comment: "Zoom User ID"
    t.string "user_name", limit: 255, null: false, comment: "사용자 이름"
    t.string "user_email", limit: 255, null: false, comment: "사용자 이메일"
    t.integer "duration", default: 0, null: false, comment: "참여 시간 (초)"
    t.string "join_time", limit: 30, null: false, comment: "참여 시작 시간"
    t.string "leave_time", limit: 30, null: false, comment: "참여 종료 시간"
    t.string "status", limit: 30, null: false, comment: "참여 상태"
    t.integer "viewer_rating", default: 0, null: false, comment: "참여율 (0-100)"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false, comment: "생성 시간"
    t.index ["content_tag_id", "meeting_id", "user_email", "join_time", "leave_time"], name: "uq_zoom_view_logs_content_meeting_user_time", unique: true
    t.index ["content_tag_id"], name: "idx_zoom_view_logs_content_tag_id"
    t.index ["join_time"], name: "idx_zoom_view_logs_join_time"
    t.index ["leave_time"], name: "idx_zoom_view_logs_leave_time"
    t.index ["meeting_id"], name: "idx_zoom_view_logs_meeting_id"
    t.index ["user_email"], name: "idx_zoom_view_logs_user_email"
    t.check_constraint "viewer_rating >= 0 AND viewer_rating <= 100", name: "chk_zoom_view_logs_viewer_rating_range"
  end

  create_table "zoom_view_results", id: :serial, comment: "Zoom 출결 결과 (외부 시스템 INSERT)", force: :cascade do |t|
    t.bigint "content_tag_id", null: false, comment: "Canvas Content Tag ID"
    t.string "meeting_id", limit: 255, null: false, comment: "Zoom Meeting ID"
    t.string "user_email", limit: 255, null: false, comment: "사용자 이메일"
    t.integer "attendance_state", default: 0, null: false, comment: "출결 상태 (0:미결, 1:결석, 2:지각, 3:공결, 4:출석)"
    t.integer "teacher_forced_change", default: 0, null: false, comment: "교수 강제 변경 (0:자동, 1:수동)"
    t.bigint "modified_by_user_id", default: 0, null: false, comment: "변경한 교수 ID"
    t.datetime "created_at", precision: nil, default: -> { "now()" }, null: false, comment: "생성 시간"
    t.datetime "updated_at", precision: nil, default: -> { "now()" }, null: false, comment: "수정 시간"
    t.index ["content_tag_id", "meeting_id", "user_email"], name: "uq_zoom_view_results_content_meeting_user", unique: true
    t.index ["content_tag_id", "user_email", "teacher_forced_change", "created_at"], name: "idx_zoom_view_results_priority"
    t.index ["content_tag_id"], name: "idx_zoom_view_results_content_tag_id"
    t.index ["meeting_id"], name: "idx_zoom_view_results_meeting_id"
    t.index ["user_email"], name: "idx_zoom_view_results_user_email"
    t.check_constraint "attendance_state >= 0 AND attendance_state <= 4", name: "chk_zoom_view_results_attendance_state"
  end

  add_foreign_key "attendance_sessions", "lti_contexts"
  add_foreign_key "live_settings", "attendance_sessions"
  add_foreign_key "projects", "lti_contexts"
  add_foreign_key "vod_settings", "attendance_sessions"
end
