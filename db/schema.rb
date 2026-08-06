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

ActiveRecord::Schema[8.2].define(version: 2026_08_06_210001) do
  create_table "account_users", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id"], name: "index_account_users_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false, collation: "NOCASE"
    t.string "slug", null: false
    t.integer "owner_id", null: false
    t.string "domain"
    t.string "contact_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "design"
    t.string "site_build_status"
    t.datetime "site_built_at"
    t.datetime "ses_tenant_provisioned_at"
    t.string "handle"
    t.index ["domain"], name: "index_accounts_on_domain", unique: true
    t.index ["handle"], name: "index_accounts_on_handle", unique: true
    t.index ["name"], name: "index_accounts_on_name", unique: true
    t.index ["owner_id"], name: "index_accounts_on_owner_id"
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

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

  create_table "ahoy_events", force: :cascade do |t|
    t.integer "visit_id"
    t.integer "user_id"
    t.string "name"
    t.text "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.integer "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.string "country_code"
    t.integer "account_id"
    t.index ["account_id"], name: "index_ahoy_visits_on_account_id"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "authors", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "default", default: false, null: false
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "tagline"
    t.index ["creator_id"], name: "index_authors_on_creator_id"
    t.index ["record_id", "id"], name: "index_authors_on_record_id_and_id"
    t.index ["record_id"], name: "index_authors_on_record_id"
  end

  create_table "beats", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.date "asked_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_beats_on_creator_id"
    t.index ["record_id", "id"], name: "index_beats_on_record_id_and_id"
  end

  create_table "bodies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "books", force: :cascade do |t|
    t.string "title", null: false
    t.string "status", default: "drafted", null: false
    t.datetime "published_at"
    t.datetime "pinned_at"
    t.date "publication_date"
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.integer "body_id", null: false
    t.integer "depiction_id"
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "author_record_id"
    t.index ["author_record_id"], name: "index_books_on_author_record_id"
    t.index ["body_id"], name: "index_books_on_body_id"
    t.index ["creator_id"], name: "index_books_on_creator_id"
    t.index ["depiction_id"], name: "index_books_on_depiction_id"
    t.index ["record_id", "id"], name: "index_books_on_record_id_and_id"
    t.index ["record_id"], name: "index_books_on_record_id"
    t.index ["status", "published_at"], name: "index_books_on_status_and_published_at"
  end

  create_table "boosts", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_boosts_on_creator_id"
    t.index ["record_id", "id"], name: "index_boosts_on_record_id_and_id"
  end

  create_table "broadcast_deliveries", force: :cascade do |t|
    t.integer "broadcast_id", null: false
    t.integer "subscriber_id", null: false
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.datetime "opened_at"
    t.datetime "clicked_at"
    t.datetime "bounced_at"
    t.datetime "complained_at"
    t.datetime "unsubscribed_at"
    t.string "provider"
    t.string "provider_message_id"
    t.index ["broadcast_id", "subscriber_id"], name: "index_broadcast_deliveries_on_broadcast_id_and_subscriber_id", unique: true
    t.index ["broadcast_id"], name: "index_broadcast_deliveries_on_broadcast_id"
    t.index ["subscriber_id"], name: "index_broadcast_deliveries_on_subscriber_id"
  end

  create_table "broadcasts", force: :cascade do |t|
    t.integer "record_id", null: false
    t.datetime "sent_at"
    t.integer "recipients_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "scheduled_at"
    t.integer "delivered_count", default: 0, null: false
    t.integer "opened_count", default: 0, null: false
    t.integer "clicked_count", default: 0, null: false
    t.integer "bounced_count", default: 0, null: false
    t.integer "complained_count", default: 0, null: false
    t.integer "unsubscribed_count", default: 0, null: false
    t.index ["record_id"], name: "index_broadcasts_on_record_id", unique: true
  end

  create_table "bulletins", force: :cascade do |t|
    t.string "title", null: false
    t.string "status", default: "drafted", null: false
    t.datetime "published_at"
    t.datetime "pinned_at"
    t.integer "record_id"
    t.integer "creator_id", null: false
    t.integer "body_id", null: false
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_id"], name: "index_bulletins_on_record_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "icon", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "account_id", null: false
    t.index ["account_id", "name"], name: "index_categories_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_categories_on_account_id"
  end

  create_table "chat_lines", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_chat_lines_on_creator_id"
    t.index ["record_id", "id"], name: "index_chat_lines_on_record_id_and_id"
  end

  create_table "circle_invitations", force: :cascade do |t|
    t.integer "circle_id", null: false
    t.integer "user_id", null: false
    t.integer "inviter_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["circle_id", "user_id"], name: "index_circle_invitations_on_circle_id_and_user_id", unique: true
    t.index ["inviter_id"], name: "index_circle_invitations_on_inviter_id"
    t.index ["user_id"], name: "index_circle_invitations_on_user_id"
  end

  create_table "circle_memberships", force: :cascade do |t|
    t.integer "circle_id", null: false
    t.integer "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["circle_id", "user_id"], name: "index_circle_memberships_on_circle_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_circle_memberships_on_user_id"
  end

  create_table "circles", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "owner_id", null: false
    t.integer "member_limit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.index ["owner_id"], name: "index_circles_on_owner_id"
    t.index ["slug"], name: "index_circles_on_slug", unique: true
  end

  create_table "collections", force: :cascade do |t|
    t.string "title", null: false
    t.string "status", default: "drafted", null: false
    t.datetime "published_at"
    t.datetime "pinned_at"
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.integer "body_id", null: false
    t.string "event", default: "created", null: false
    t.integer "author_record_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_record_id"], name: "index_collections_on_author_record_id"
    t.index ["body_id"], name: "index_collections_on_body_id"
    t.index ["creator_id"], name: "index_collections_on_creator_id"
    t.index ["record_id", "id"], name: "index_collections_on_record_id_and_id"
    t.index ["record_id"], name: "index_collections_on_record_id"
    t.index ["status", "published_at"], name: "index_collections_on_status_and_published_at"
  end

  create_table "comments", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_comments_on_creator_id"
    t.index ["record_id", "id"], name: "index_comments_on_record_id_and_id"
  end

  create_table "custom_domains", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "hostname", null: false
    t.boolean "canonical", default: false, null: false
    t.string "status", default: "pending", null: false
    t.string "cloudflare_id"
    t.string "ssl_status"
    t.string "txt_name"
    t.string "txt_value"
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_domains_on_account_id"
    t.index ["hostname"], name: "index_custom_domains_on_hostname", unique: true
  end

  create_table "delivery_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event", null: false
    t.string "provider_message_id"
    t.string "recipient"
    t.integer "subscriber_id"
    t.string "delivery_type"
    t.integer "delivery_id"
    t.json "payload", null: false
    t.datetime "occurred_at"
    t.datetime "created_at", null: false
    t.index ["delivery_type", "delivery_id"], name: "index_delivery_events_on_delivery"
    t.index ["provider", "provider_message_id", "event"], name: "index_delivery_events_on_dedupe_key", unique: true
    t.index ["subscriber_id"], name: "index_delivery_events_on_subscriber_id"
  end

  create_table "depictions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "distributors", force: :cascade do |t|
    t.integer "record_id", null: false
    t.string "url", null: false
    t.string "platform", null: false
    t.integer "clicks", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_id", "url"], name: "index_distributors_on_record_id_and_url", unique: true
    t.index ["record_id"], name: "index_distributors_on_record_id"
  end

  create_table "drips", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.string "title", null: false
    t.boolean "active", default: false, null: false
    t.string "trigger", default: "confirmed", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_drips_on_creator_id"
    t.index ["record_id", "id"], name: "index_drips_on_record_id_and_id"
  end

  create_table "drop_deliveries", force: :cascade do |t|
    t.integer "stream_id", null: false
    t.integer "drop_record_id", null: false
    t.integer "subscriber_id", null: false
    t.string "status", default: "pending", null: false
    t.string "skip_reason"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "opened_at"
    t.datetime "clicked_at"
    t.datetime "bounced_at"
    t.datetime "complained_at"
    t.datetime "unsubscribed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "provider_message_id"
    t.index ["drop_record_id"], name: "index_drop_deliveries_on_drop_record_id"
    t.index ["stream_id", "drop_record_id"], name: "index_drop_deliveries_on_stream_id_and_drop_record_id", unique: true
    t.index ["stream_id"], name: "index_drop_deliveries_on_stream_id"
    t.index ["subscriber_id"], name: "index_drop_deliveries_on_subscriber_id"
  end

  create_table "drops", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.string "subject", null: false
    t.integer "delay_days", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_drops_on_creator_id"
    t.index ["record_id", "id"], name: "index_drops_on_record_id_and_id"
  end

  create_table "goals", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.string "title", null: false
    t.string "unit", default: "words", null: false
    t.integer "target"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "per"
    t.text "displays"
    t.date "starts_on"
    t.date "ends_on"
    t.index ["creator_id"], name: "index_goals_on_creator_id"
    t.index ["record_id", "id"], name: "index_goals_on_record_id_and_id"
  end

  create_table "installments", force: :cascade do |t|
    t.integer "container_record_id", null: false
    t.integer "book_record_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_record_id"], name: "index_installments_on_book_record_id"
    t.index ["container_record_id", "book_record_id"], name: "index_installments_on_container_record_id_and_book_record_id", unique: true
    t.index ["container_record_id", "position"], name: "index_installments_on_container_record_id_and_position"
  end

  create_table "join_codes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "code", null: false
    t.datetime "rotated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_join_codes_on_code", unique: true
    t.index ["user_id"], name: "index_join_codes_on_user_id", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.string "title", null: false
    t.string "status", default: "drafted", null: false
    t.datetime "published_at"
    t.datetime "pinned_at"
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.integer "body_id", null: false
    t.integer "category_id"
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["body_id"], name: "index_messages_on_body_id"
    t.index ["category_id"], name: "index_messages_on_category_id"
    t.index ["creator_id"], name: "index_messages_on_creator_id"
    t.index ["record_id", "id"], name: "index_messages_on_record_id_and_id"
    t.index ["record_id"], name: "index_messages_on_record_id"
    t.index ["status", "published_at"], name: "index_messages_on_status_and_published_at"
  end

  create_table "missives", force: :cascade do |t|
    t.string "name", null: false
    t.string "email_address", null: false
    t.string "subject", null: false
    t.text "body", null: false
    t.datetime "confirmed_at"
    t.string "consent_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "trashed_at"
    t.integer "account_id"
    t.string "source_message_id"
    t.index ["account_id"], name: "index_missives_on_account_id"
    t.index ["confirmed_at"], name: "index_missives_on_confirmed_at"
    t.index ["created_at"], name: "index_missives_on_created_at"
    t.index ["source_message_id"], name: "index_missives_on_source_message_id", unique: true, where: "source_message_id IS NOT NULL"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "source_type"
    t.integer "source_id"
    t.string "kind", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "actor_id"
    t.string "title"
    t.string "url"
    t.datetime "emailed_at"
    t.index ["source_type", "source_id"], name: "index_notifications_on_source_type_and_source_id"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
  end

  create_table "people", force: :cascade do |t|
    t.string "email_address", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_people_on_email_address", unique: true
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
    t.text "excerpt"
    t.integer "author_record_id"
    t.index ["author_record_id"], name: "index_posts_on_author_record_id"
    t.index ["body_id"], name: "index_posts_on_body_id"
    t.index ["creator_id"], name: "index_posts_on_creator_id"
    t.index ["record_id", "id"], name: "index_posts_on_record_id_and_id"
    t.index ["record_id"], name: "index_posts_on_record_id"
    t.index ["status", "published_at"], name: "index_posts_on_status_and_published_at"
  end

  create_table "pulse_subscriptions", force: :cascade do |t|
    t.integer "pulse_record_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pulse_record_id", "user_id"], name: "index_pulse_subscriptions_on_pulse_record_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_pulse_subscriptions_on_user_id"
  end

  create_table "pulses", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.text "question", null: false
    t.string "cadence", default: "weekly", null: false
    t.integer "days_of_week", default: 0, null: false
    t.integer "ask_at_minutes", default: 540, null: false
    t.boolean "active", default: true, null: false
    t.date "last_asked_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_pulses_on_creator_id"
    t.index ["record_id", "id"], name: "index_pulses_on_record_id_and_id"
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
    t.string "bucket_type"
    t.integer "bucket_id"
    t.datetime "archived_at"
    t.index ["bucket_type", "bucket_id", "recordable_type"], name: "index_records_on_bucket_and_recordable_type"
    t.index ["creator_id"], name: "index_records_on_creator_id"
    t.index ["parent_id"], name: "index_records_on_parent_id"
    t.index ["purge_after"], name: "index_records_on_purge_after"
    t.index ["recordable_type", "recordable_id"], name: "index_records_on_recordable_type_and_recordable_id", unique: true
  end

  create_table "sending_domains", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "domain", null: false
    t.string "status", default: "pending", null: false
    t.json "dkim_tokens"
    t.string "mail_from_domain"
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sending_domains_on_account_id"
    t.index ["domain"], name: "index_sending_domains_on_domain", unique: true
  end

  create_table "series", force: :cascade do |t|
    t.string "title", null: false
    t.string "status", default: "drafted", null: false
    t.datetime "published_at"
    t.datetime "pinned_at"
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.integer "body_id", null: false
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "author_record_id"
    t.index ["author_record_id"], name: "index_series_on_author_record_id"
    t.index ["body_id"], name: "index_series_on_body_id"
    t.index ["creator_id"], name: "index_series_on_creator_id"
    t.index ["record_id", "id"], name: "index_series_on_record_id_and_id"
    t.index ["record_id"], name: "index_series_on_record_id"
    t.index ["status", "published_at"], name: "index_series_on_status_and_published_at"
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

  create_table "sites", force: :cascade do |t|
    t.string "site_name", null: false
    t.string "tagline"
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_id", "id"], name: "index_sites_on_record_id_and_id"
    t.index ["record_id"], name: "index_sites_on_record_id"
  end

  create_table "streams", force: :cascade do |t|
    t.integer "subscriber_id", null: false
    t.integer "drip_record_id", null: false
    t.datetime "enrolled_at", null: false
    t.datetime "ended_at"
    t.string "ended_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["drip_record_id"], name: "index_streams_on_drip_record_id"
    t.index ["subscriber_id", "drip_record_id"], name: "index_streams_on_subscriber_id_and_drip_record_id", unique: true
    t.index ["subscriber_id"], name: "index_streams_on_subscriber_id"
  end

  create_table "subscribers", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "status", default: "pending", null: false
    t.datetime "confirmed_at"
    t.datetime "unsubscribed_at"
    t.string "source"
    t.string "consent_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_engaged_at"
    t.datetime "re_engagement_sent_at"
    t.integer "account_id", null: false
    t.integer "person_id", null: false
    t.boolean "seed", default: false, null: false
    t.index ["account_id", "status"], name: "index_subscribers_on_account_id_and_status"
    t.index ["email_address"], name: "index_subscribers_on_email_address"
    t.index ["person_id", "account_id"], name: "index_subscribers_on_person_id_and_account_id", unique: true
    t.index ["person_id"], name: "index_subscribers_on_person_id"
    t.index ["status", "last_engaged_at"], name: "index_subscribers_on_status_and_last_engaged_at"
  end

  create_table "subscription_events", force: :cascade do |t|
    t.integer "subscriber_id", null: false
    t.string "action", null: false
    t.string "ip_address"
    t.string "source"
    t.datetime "created_at", null: false
    t.index ["subscriber_id"], name: "index_subscription_events_on_subscriber_id"
  end

  create_table "tallies", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.date "logged_on", null: false
    t.integer "amount", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_tallies_on_creator_id"
    t.index ["record_id", "id"], name: "index_tallies_on_record_id_and_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.integer "record_id", null: false
    t.integer "creator_id", null: false
    t.string "event", default: "created", null: false
    t.string "title", null: false
    t.string "status", default: "open", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_tickets_on_creator_id"
    t.index ["record_id", "id"], name: "index_tickets_on_record_id_and_id"
    t.index ["record_id"], name: "index_tickets_on_record_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "member", null: false
    t.integer "inviter_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["inviter_id"], name: "index_users_on_inviter_id"
    t.index ["name"], name: "index_users_on_name", unique: true
  end

  add_foreign_key "account_users", "accounts"
  add_foreign_key "account_users", "users"
  add_foreign_key "accounts", "users", column: "owner_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ahoy_visits", "accounts"
  add_foreign_key "boosts", "records"
  add_foreign_key "boosts", "users", column: "creator_id"
  add_foreign_key "broadcast_deliveries", "broadcasts"
  add_foreign_key "broadcast_deliveries", "subscribers"
  add_foreign_key "categories", "accounts"
  add_foreign_key "custom_domains", "accounts"
  add_foreign_key "drop_deliveries", "records", column: "drop_record_id"
  add_foreign_key "drop_deliveries", "streams"
  add_foreign_key "drop_deliveries", "subscribers"
  add_foreign_key "join_codes", "users"
  add_foreign_key "messages", "bodies"
  add_foreign_key "messages", "categories"
  add_foreign_key "messages", "records"
  add_foreign_key "messages", "users", column: "creator_id"
  add_foreign_key "missives", "accounts"
  add_foreign_key "posts", "bodies"
  add_foreign_key "posts", "records"
  add_foreign_key "posts", "users", column: "creator_id"
  add_foreign_key "pulse_subscriptions", "users"
  add_foreign_key "records", "records", column: "parent_id"
  add_foreign_key "records", "users", column: "creator_id"
  add_foreign_key "sending_domains", "accounts"
  add_foreign_key "sessions", "users"
  add_foreign_key "sign_in_codes", "users"
  add_foreign_key "sites", "records"
  add_foreign_key "sites", "users", column: "creator_id"
  add_foreign_key "streams", "records", column: "drip_record_id"
  add_foreign_key "streams", "subscribers"
  add_foreign_key "subscribers", "accounts"
  add_foreign_key "subscribers", "people"
  add_foreign_key "subscription_events", "subscribers"
  add_foreign_key "users", "users", column: "inviter_id"
end
