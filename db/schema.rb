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

ActiveRecord::Schema[7.1].define(version: 201811070122202) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.string "status", default: "succeeded", null: false
    t.string "source"
    t.string "actor"
    t.bigint "actor_user_id"
    t.json "metadata"
    t.datetime "created_at", precision: nil, null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_user_id"], name: "index_audit_logs_on_actor_user_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
  end

  create_table "categories", force: :cascade do |t|
    t.string "category_name"
    t.decimal "default_node_price", precision: 10, scale: 2
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.decimal "price", precision: 10
    t.bigint "default_unit_id"
    t.integer "kind", default: 0, null: false
    t.index ["default_unit_id"], name: "index_categories_on_default_unit_id"
  end

  create_table "category_sizes", force: :cascade do |t|
    t.integer "user_id"
    t.integer "category_id", null: false
    t.integer "item_unit_id", null: false
    t.float "quantity"
    t.float "price"
    t.decimal "quantity_canonical", precision: 14, scale: 4
    t.integer "canonical_unit_type"
    t.index ["user_id", "category_id"], name: "index_category_sizes_on_user_and_category"
  end

  create_table "category_units", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.bigint "item_unit_id", null: false
    t.integer "display_order", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["category_id", "item_unit_id"], name: "index_category_units_on_category_id_and_item_unit_id", unique: true
    t.index ["category_id"], name: "index_category_units_on_category_id"
    t.index ["item_unit_id"], name: "index_category_units_on_item_unit_id"
  end

  create_table "foaf_outbox_entries", force: :cascade do |t|
    t.bigint "trustline_id", null: false
    t.string "operation_type", limit: 32, null: false
    t.json "payload", null: false
    t.string "foaf_write_state", default: "pending", null: false
    t.text "foaf_write_error"
    t.datetime "foaf_posted_at"
    t.datetime "superseded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_type", "foaf_posted_at", "superseded_at"], name: "index_foaf_outbox_entries_for_replay"
    t.index ["trustline_id", "operation_type", "created_at"], name: "index_foaf_outbox_entries_on_trustline_operation"
    t.index ["trustline_id"], name: "index_foaf_outbox_entries_on_trustline_id"
  end

  create_table "global_settings", force: :cascade do |t|
    t.integer "value", default: 3
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "setting", default: ""
    t.text "string_value"
  end

  create_table "grades", force: :cascade do |t|
    t.string "name"
    t.string "value"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "introductions", force: :cascade do |t|
    t.bigint "introducer_id", null: false
    t.bigint "introducee_a_id", null: false
    t.bigint "introducee_b_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "accepted_a_at", precision: nil
    t.datetime "accepted_b_at", precision: nil
    t.integer "declined_by_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["introducee_a_id"], name: "index_introductions_on_introducee_a_id"
    t.index ["introducee_b_id"], name: "index_introductions_on_introducee_b_id"
    t.index ["introducer_id", "status"], name: "index_introductions_on_introducer_and_status"
  end

  create_table "inventories", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "item_id"
    t.float "quantity"
    t.decimal "price", precision: 10, scale: 2
    t.integer "status"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "ref_id"
    t.json "avatars"
    t.string "gallery_map", default: "---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n"
    t.float "ref_price"
    t.text "description"
    t.boolean "apply_first_hop_markup", default: false, null: false
    t.decimal "quantity_canonical", precision: 14, scale: 4, null: false
    t.integer "canonical_unit_type"
    t.index ["item_id"], name: "index_inventories_on_item_id"
    t.index ["ref_id"], name: "index_inventories_on_ref_id"
    t.index ["user_id", "status"], name: "index_inventories_on_user_id_and_status"
    t.index ["user_id"], name: "index_inventories_on_user_id"
  end

  create_table "invitation_redemptions", force: :cascade do |t|
    t.bigint "invitation_id"
    t.bigint "user_id"
    t.datetime "redeemed_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["invitation_id", "user_id"], name: "index_invitation_redemptions_on_invitation_and_user", unique: true
    t.index ["user_id"], name: "index_invitation_redemptions_on_user_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.string "invitation_code"
    t.bigint "user_id"
    t.integer "status"
    t.string "label", default: ""
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_type", default: 0
    t.string "note_label"
    t.integer "accepted_id"
    t.float "user_price"
    t.bigint "subnet_id"
    t.string "app_onboarding_status", default: "pending", null: false
    t.string "app_onboarding_rejection_code"
    t.datetime "app_onboarding_completed_at", precision: nil
    t.json "subnet_seed_config"
    t.boolean "multi_use", default: false, null: false
    t.datetime "disabled_at", precision: nil
    t.index ["app_onboarding_status", "user_id"], name: "index_invitations_on_app_onboarding_status_user"
    t.index ["invitation_code"], name: "index_invitations_on_invitation_code"
    t.index ["subnet_id"], name: "index_invitations_on_subnet_id"
    t.index ["user_id"], name: "index_invitations_on_user_id"
  end

  create_table "item_names", force: :cascade do |t|
    t.string "name"
    t.bigint "category_id"
    t.text "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["category_id"], name: "index_item_names_on_category_id"
  end

  create_table "item_relationships", force: :cascade do |t|
    t.bigint "item_id"
    t.bigint "relationship_id"
    t.boolean "status"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["item_id"], name: "index_item_relationships_on_item_id"
    t.index ["relationship_id"], name: "index_item_relationships_on_relationship_id"
  end

  create_table "item_requests", force: :cascade do |t|
    t.bigint "user_id"
    t.decimal "price", precision: 10, scale: 2
    t.integer "status"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "friend_id"
    t.bigint "request_contract_id"
    t.boolean "sent", default: false, null: false
    t.integer "step", default: 0
    t.datetime "accepted_at", precision: nil
    t.datetime "shipped_at", precision: nil
    t.datetime "signed_at", precision: nil
    t.integer "order_id"
    t.text "cancellation_reason"
    t.index ["friend_id"], name: "index_item_requests_on_friend_id"
    t.index ["order_id"], name: "index_item_requests_on_order_id"
    t.index ["request_contract_id"], name: "index_item_requests_on_request_contract_id"
    t.index ["user_id"], name: "index_item_requests_on_user_id"
  end

  create_table "item_units", force: :cascade do |t|
    t.string "unit_name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.float "equivalent"
    t.string "item_symbol"
    t.integer "unit_type", default: 0, null: false
  end

  create_table "items", force: :cascade do |t|
    t.bigint "user_id"
    t.decimal "quantity", precision: 10, scale: 5
    t.bigint "category_id"
    t.bigint "item_name_id"
    t.string "name"
    t.bigint "grade_id"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "date_available", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "item_unit_id"
    t.boolean "organic", default: false
    t.integer "producer_id"
    t.json "avatars"
    t.decimal "pack_contains_quantity", precision: 14, scale: 4
    t.bigint "pack_contains_unit_id"
    t.integer "condition"
    t.boolean "one_time_listing", default: false, null: false
    t.integer "pricing_basis", default: 0, null: false
    t.string "sale_unit_label"
    t.decimal "est_weight_min", precision: 10, scale: 2
    t.decimal "est_weight_max", precision: 10, scale: 2
    t.decimal "cut_yield_factor", precision: 4, scale: 3, default: "0.6"
    t.boolean "on_the_rail_available", default: false, null: false
    t.decimal "on_the_rail_delta", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["category_id"], name: "index_items_on_category_id"
    t.index ["grade_id"], name: "index_items_on_grade_id"
    t.index ["item_name_id"], name: "index_items_on_item_name_id"
    t.index ["item_unit_id"], name: "index_items_on_item_unit_id"
    t.index ["pack_contains_unit_id"], name: "index_items_on_pack_contains_unit_id"
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "jwt_blacklist", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", precision: nil, null: false
    t.index ["jti"], name: "index_jwt_blacklist_on_jti"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "recipient_id", null: false
    t.bigint "actor_id"
    t.string "notification_type", null: false
    t.text "message", null: false
    t.string "actor_name"
    t.string "actor_avatar_url"
    t.string "target_type"
    t.bigint "target_id"
    t.string "target_screen"
    t.json "metadata"
    t.boolean "read", default: false, null: false
    t.datetime "read_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.datetime "resolved_at", precision: nil
    t.string "resolution_reason"
    t.index ["actor_id"], name: "fk_rails_06a39bb8cc"
    t.index ["recipient_id", "created_at"], name: "index_notifications_timeline"
    t.index ["recipient_id", "read", "created_at"], name: "index_notifications_inbox"
    t.index ["recipient_id", "resolved_at"], name: "index_notifications_on_recipient_and_resolved"
    t.index ["subject_type", "subject_id"], name: "index_notifications_on_subject"
  end

  create_table "orders", force: :cascade do |t|
    t.string "user_id"
    t.string "friend_id"
    t.string "order_label"
    t.integer "order_status"
    t.datetime "estimated_date", precision: nil
    t.datetime "shipped_on", precision: nil
    t.datetime "signed_on", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.time "estimated_time"
    t.string "location", default: "pick up", null: false
    t.text "note"
    t.string "settlement_type"
    t.string "settlement_status"
    t.integer "settlement_proposed_by"
    t.string "settlement_counter_type"
    t.integer "settlement_counter_by"
    t.decimal "cash_amount", precision: 10, scale: 2
    t.integer "cash_paid_by"
    t.integer "cash_confirmed_by"
    t.index ["friend_id"], name: "index_orders_on_friend_id"
    t.index ["user_id", "friend_id", "order_status"], name: "index_orders_on_user_friend_status"
  end

  create_table "pending_payments", force: :cascade do |t|
    t.bigint "from_user_id"
    t.bigint "to_user_id"
    t.bigint "trustline_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.text "rejected_reason"
    t.datetime "confirmed_at", precision: nil
    t.datetime "resolved_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "kind", default: 0, null: false
    t.datetime "paid_at", precision: nil
    t.index ["from_user_id"], name: "index_pending_payments_on_from_user_id"
    t.index ["kind"], name: "index_pending_payments_on_kind"
    t.index ["status"], name: "index_pending_payments_on_status"
    t.index ["to_user_id"], name: "index_pending_payments_on_to_user_id"
    t.index ["trustline_id"], name: "index_pending_payments_on_trustline_id"
  end

  create_table "push_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token", null: false
    t.string "device_id", null: false
    t.string "platform", null: false
    t.datetime "last_seen_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["token"], name: "index_push_tokens_on_token", unique: true
    t.index ["user_id", "device_id"], name: "index_push_tokens_on_user_id_and_device_id", unique: true
    t.index ["user_id"], name: "index_push_tokens_on_user_id"
  end

  create_table "relationships", force: :cascade do |t|
    t.integer "friend_id"
    t.integer "status", default: 0
    t.integer "action_user_id"
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "user_label"
    t.string "friend_label"
    t.integer "actions_state", default: 0
    t.integer "friend_actions_state", default: 0
    t.index ["friend_id"], name: "index_relationships_on_friend_id"
    t.index ["user_id"], name: "index_relationships_on_user_id"
  end

  create_table "request_contracts", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "item_id"
    t.decimal "quantity", precision: 10, scale: 5
    t.integer "status", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "inventory_id"
    t.integer "steps", default: 0
    t.integer "current_step", default: 0
    t.datetime "deleted_at", precision: nil
    t.datetime "deleted_by", precision: nil
    t.boolean "archived", default: false
    t.string "unit"
    t.index ["inventory_id"], name: "index_request_contracts_on_inventory_id"
    t.index ["item_id"], name: "index_request_contracts_on_item_id"
    t.index ["user_id"], name: "index_request_contracts_on_user_id"
  end

  create_table "request_list_relationship_statuses", force: :cascade do |t|
    t.bigint "relationship_id"
    t.string "status"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "item_request_id"
    t.index ["item_request_id"], name: "index_request_list_relationship_statuses_on_item_request_id"
    t.index ["relationship_id"], name: "index_request_list_relationship_statuses_on_relationship_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "item_name_id"
    t.bigint "item_id"
    t.integer "producer_id"
    t.integer "value"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["item_id"], name: "index_reviews_on_item_id"
    t.index ["item_name_id"], name: "index_reviews_on_item_name_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "subnet_applications", force: :cascade do |t|
    t.string "community_name", null: false
    t.string "location", null: false
    t.string "contact_name", null: false
    t.string "contact_email", null: false
    t.text "description"
    t.string "status", default: "pending", null: false
    t.bigint "reviewed_by_user_id"
    t.datetime "reviewed_at", precision: nil
    t.bigint "created_subnet_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["created_at"], name: "index_subnet_applications_on_created_at"
    t.index ["location"], name: "index_subnet_applications_on_location"
    t.index ["status"], name: "index_subnet_applications_on_status"
  end

  create_table "subnet_configs", force: :cascade do |t|
    t.bigint "subnet_id", null: false
    t.integer "version", null: false
    t.json "config", null: false
    t.bigint "changed_by_user_id"
    t.datetime "created_at", precision: nil, null: false
    t.index ["subnet_id", "version"], name: "index_subnet_configs_on_subnet_id_and_version", unique: true
  end

  create_table "subnet_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "subnet_id", null: false
    t.bigint "joined_via_invitation_id"
    t.boolean "is_primary", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["joined_via_invitation_id"], name: "index_subnet_memberships_on_joined_via_invitation_id"
    t.index ["subnet_id"], name: "index_subnet_memberships_on_subnet_id"
    t.index ["user_id", "subnet_id"], name: "index_subnet_memberships_on_user_id_and_subnet_id", unique: true
  end

  create_table "subnets", force: :cascade do |t|
    t.bigint "seed_user_id", null: false
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["seed_user_id"], name: "index_subnets_on_seed_user_id"
  end

  create_table "trustline_transactions", force: :cascade do |t|
    t.bigint "trustline_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.text "description"
    t.bigint "originating_request_id"
    t.bigint "order_id"
    t.json "path_info"
    t.string "transaction_type", null: false
    t.bigint "initiated_by_id", null: false
    t.decimal "balance_after", precision: 10, scale: 2
    t.boolean "is_reversed", default: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "foaf_operation_id"
    t.datetime "foaf_posted_at", precision: nil
    t.string "foaf_direction", limit: 16
    t.bigint "foaf_pending_transfer_id"
    t.string "foaf_write_state"
    t.text "foaf_write_error"
    t.index ["created_at"], name: "index_trustline_transactions_on_created_at"
    t.index ["foaf_pending_transfer_id"], name: "index_trustline_transactions_on_foaf_pending_transfer_id"
    t.index ["foaf_posted_at"], name: "index_trustline_transactions_on_foaf_posted_at"
    t.index ["foaf_write_state"], name: "index_trustline_transactions_on_foaf_write_state"
    t.index ["initiated_by_id"], name: "index_trustline_transactions_on_initiated_by_id"
    t.index ["is_reversed"], name: "index_trustline_transactions_on_is_reversed"
    t.index ["order_id"], name: "index_trustline_transactions_on_order_id"
    t.index ["originating_request_id"], name: "index_trustline_transactions_on_originating_request_id"
    t.index ["transaction_type"], name: "index_trustline_transactions_on_transaction_type"
    t.index ["trustline_id"], name: "index_trustline_transactions_on_trustline_id"
  end

  create_table "trustlines", force: :cascade do |t|
    t.bigint "user_a_id", null: false
    t.bigint "user_b_id", null: false
    t.decimal "credit_limit_a_to_b", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "credit_limit_b_to_a", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "current_balance", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "established_date", precision: nil, null: false
    t.datetime "last_activity", precision: nil
    t.text "notes"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["established_date"], name: "index_trustlines_on_established_date"
    t.index ["is_active"], name: "index_trustlines_on_is_active"
    t.index ["user_a_id", "user_b_id"], name: "index_trustlines_on_user_pair", unique: true
    t.index ["user_a_id"], name: "index_trustlines_on_user_a_id"
    t.index ["user_b_id"], name: "index_trustlines_on_user_b_id"
  end

  create_table "unit_options", force: :cascade do |t|
    t.integer "inventory_id", null: false
    t.integer "item_unit_id", null: false
    t.float "price"
    t.float "quantity"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.decimal "quantity_canonical", precision: 14, scale: 4
    t.integer "canonical_unit_type"
    t.string "label"
    t.index ["inventory_id"], name: "index_unit_options_on_inventory_id"
  end

  create_table "user_category_prices", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "category_id"
    t.decimal "price", precision: 10, scale: 2
    t.string "unit"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "price_type", default: "flat", null: false
    t.index ["category_id"], name: "index_user_category_prices_on_category_id"
    t.index ["user_id"], name: "index_user_category_prices_on_user_id"
  end

  create_table "user_groups", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "group_label"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["user_id"], name: "index_user_groups_on_user_id"
  end

  create_table "user_relationship_prices", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "friend_id"
    t.bigint "category_id"
    t.bigint "relationship_id"
    t.decimal "price", precision: 10, scale: 2
    t.decimal "receiving_price", precision: 10, scale: 2
    t.string "receiving_price_type"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "price_type", default: "flat", null: false
    t.index ["category_id"], name: "index_user_relationship_prices_on_category_id"
    t.index ["relationship_id"], name: "index_user_relationship_prices_on_relationship_id"
    t.index ["user_id"], name: "index_user_relationship_prices_on_user_id"
  end

  create_table "user_relationship_request_prices", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "friend_id"
    t.bigint "relationship_id"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "item_request_id"
    t.index ["item_request_id"], name: "index_user_relationship_request_prices_on_item_request_id"
    t.index ["relationship_id"], name: "index_user_relationship_request_prices_on_relationship_id"
    t.index ["user_id"], name: "index_user_relationship_request_prices_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "name"
    t.string "nickname"
    t.string "image"
    t.string "email"
    t.text "tokens"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "invitation_limit"
    t.bigint "invited_by_id"
    t.integer "invitations_count", default: 0
    t.string "user_name", default: "", null: false
    t.string "invitation_code"
    t.integer "depth", default: 3
    t.integer "invite_limit", default: 3
    t.string "invited_code"
    t.integer "parent_id"
    t.string "foaf_address", limit: 42
    t.text "foaf_public_key"
    t.text "foaf_private_key"
    t.boolean "foaf_registered", default: false
    t.text "foaf_seed_phrase"
    t.string "foaf_id", limit: 36, null: false
    t.string "first_name"
    t.string "last_name"
    t.string "display_name"
    t.datetime "deleted_at", precision: nil
    t.datetime "disabled_at", precision: nil
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.boolean "location_opted_in", default: false, null: false
    t.datetime "location_updated_at", precision: nil
    t.integer "discovery_radius_km"
    t.string "custody_state", default: "pending"
    t.text "about"
    t.string "area_label"
    t.text "offering"
    t.index ["custody_state"], name: "index_users_on_custody_state"
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["disabled_at"], name: "index_users_on_disabled_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["foaf_address"], name: "index_users_on_foaf_address", unique: true
    t.index ["foaf_id"], name: "index_users_on_foaf_id", unique: true
    t.index ["invitations_count"], name: "index_users_on_invitations_count"
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_id"], name: "index_users_on_invited_by_type_and_invited_by_id"
    t.index ["latitude", "longitude"], name: "index_users_on_latitude_and_longitude"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["user_name"], name: "index_users_on_user_name", unique: true
  end

  add_foreign_key "categories", "item_units", column: "default_unit_id"
  add_foreign_key "category_units", "categories"
  add_foreign_key "category_units", "item_units"
  add_foreign_key "foaf_outbox_entries", "trustlines", on_delete: :cascade
  add_foreign_key "introductions", "users", column: "introducee_a_id"
  add_foreign_key "introductions", "users", column: "introducee_b_id"
  add_foreign_key "introductions", "users", column: "introducer_id"
  add_foreign_key "inventories", "items"
  add_foreign_key "inventories", "users"
  add_foreign_key "invitations", "users"
  add_foreign_key "item_names", "categories"
  add_foreign_key "item_relationships", "items"
  add_foreign_key "item_relationships", "relationships"
  add_foreign_key "item_requests", "request_contracts"
  add_foreign_key "item_requests", "users"
  add_foreign_key "items", "categories"
  add_foreign_key "items", "grades"
  add_foreign_key "items", "item_names"
  add_foreign_key "items", "item_units"
  add_foreign_key "items", "item_units", column: "pack_contains_unit_id"
  add_foreign_key "items", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "pending_payments", "trustlines"
  add_foreign_key "pending_payments", "users", column: "from_user_id"
  add_foreign_key "pending_payments", "users", column: "to_user_id"
  add_foreign_key "push_tokens", "users"
  add_foreign_key "relationships", "users"
  add_foreign_key "request_contracts", "items"
  add_foreign_key "request_contracts", "users"
  add_foreign_key "request_list_relationship_statuses", "item_requests"
  add_foreign_key "request_list_relationship_statuses", "relationships"
  add_foreign_key "reviews", "item_names"
  add_foreign_key "reviews", "items"
  add_foreign_key "reviews", "users"
  add_foreign_key "trustline_transactions", "item_requests", column: "originating_request_id"
  add_foreign_key "trustline_transactions", "orders"
  add_foreign_key "trustline_transactions", "trustlines"
  add_foreign_key "trustline_transactions", "users", column: "initiated_by_id"
  add_foreign_key "trustlines", "users", column: "user_a_id"
  add_foreign_key "trustlines", "users", column: "user_b_id"
  add_foreign_key "user_category_prices", "categories"
  add_foreign_key "user_category_prices", "users"
  add_foreign_key "user_groups", "users"
  add_foreign_key "user_relationship_prices", "categories"
  add_foreign_key "user_relationship_prices", "relationships"
  add_foreign_key "user_relationship_prices", "users"
  add_foreign_key "user_relationship_request_prices", "item_requests"
  add_foreign_key "user_relationship_request_prices", "relationships"
  add_foreign_key "user_relationship_request_prices", "users"
end
