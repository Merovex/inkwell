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

ActiveRecord::Schema[8.2].define(version: 2026_07_03_300001) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bodies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "posts", force: :cascade do |t|
    t.string "title", null: false
    t.string "status", default: "drafted", null: false
    t.datetime "published_at"
    t.datetime "pinned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.integer "body_id", null: false
    t.string "event", default: "created", null: false
    t.index ["body_id"], name: "index_posts_on_body_id"
    t.index ["creator_id"], name: "index_posts_on_creator_id"
    t.index ["record_id", "id"], name: "index_posts_on_record_id_and_id"
    t.index ["record_id"], name: "index_posts_on_record_id"
    t.index ["status", "published_at"], name: "index_posts_on_status_and_published_at"
  end

  create_table "records", force: :cascade do |t|
    t.string "recordable_type", null: false
    t.bigint "recordable_id"
    t.integer "creator_id", null: false
    t.integer "parent_id"
    t.integer "position"
    t.datetime "trashed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "purge_after"
    t.index ["creator_id"], name: "index_records_on_creator_id"
    t.index ["parent_id"], name: "index_records_on_parent_id"
    t.index ["purge_after"], name: "index_records_on_purge_after"
    t.index ["recordable_type", "recordable_id"], name: "index_records_on_recordable_type_and_recordable_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sign_in_codes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "code_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_sign_in_codes_on_code_digest", unique: true
    t.index ["user_id"], name: "index_sign_in_codes_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "member", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "posts", "bodies"
  add_foreign_key "posts", "records"
  add_foreign_key "posts", "users", column: "creator_id"
  add_foreign_key "records", "records", column: "parent_id"
  add_foreign_key "records", "users", column: "creator_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "sign_in_codes", "users"
end
