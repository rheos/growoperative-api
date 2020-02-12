# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 201811070122202) do

  create_table "categories", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "category_name"
    t.integer "default_unit"
    t.integer "default_consumer_unit"
    t.decimal "default_node_price", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "price", precision: 10
  end

  create_table "global_settings", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.integer "value", default: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "setting", default: ""
  end

  create_table "grades", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "name"
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "inventories", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "item_id"
    t.float "quantity"
    t.decimal "price", precision: 10
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ref_id"
    t.json "avatars"
    t.string "gallery_map", default: "---\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n- \"<-\"\n"
    t.index ["item_id"], name: "index_inventories_on_item_id"
    t.index ["user_id"], name: "index_inventories_on_user_id"
  end

  create_table "invitations", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "invitation_code"
    t.bigint "user_id"
    t.integer "status"
    t.string "label", default: ""
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_type", default: 0
    t.string "note_label"
    t.integer "accepted_id"
    t.index ["user_id"], name: "index_invitations_on_user_id"
  end

  create_table "item_names", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "name"
    t.bigint "category_id"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_item_names_on_category_id"
  end

  create_table "item_relatiohships", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "item_id"
    t.bigint "relationship_id"
    t.boolean "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_item_relatiohships_on_item_id"
    t.index ["relationship_id"], name: "index_item_relatiohships_on_relationship_id"
  end

  create_table "item_requests", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.decimal "price", precision: 10
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "friend_id"
    t.bigint "request_contract_id"
    t.boolean "sent", default: false, null: false
    t.integer "step", default: 0
    t.datetime "accepted_at"
    t.datetime "shipped_at"
    t.datetime "signed_at"
    t.integer "order_id"
    t.index ["request_contract_id"], name: "index_item_requests_on_request_contract_id"
    t.index ["user_id"], name: "index_item_requests_on_user_id"
  end

  create_table "item_units", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "unit_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "item_symbol"
  end

  create_table "items", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.decimal "quantity", precision: 10, scale: 5
    t.bigint "category_id"
    t.bigint "item_name_id"
    t.string "name"
    t.bigint "grade_id"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "date_available"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "item_unit_id"
    t.boolean "organic", default: false
    t.integer "producer_id"
    t.json "avatars"
    t.index ["category_id"], name: "index_items_on_category_id"
    t.index ["grade_id"], name: "index_items_on_grade_id"
    t.index ["item_name_id"], name: "index_items_on_item_name_id"
    t.index ["item_unit_id"], name: "index_items_on_item_unit_id"
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "jwt_blacklist", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.index ["jti"], name: "index_jwt_blacklist_on_jti"
  end

  create_table "orders", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "user_id"
    t.string "friend_id"
    t.string "order_label"
    t.decimal "order_total", precision: 10
    t.integer "order_status"
    t.datetime "estimated_date"
    t.datetime "shipped_on"
    t.datetime "signed_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "relationships", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.integer "friend_id"
    t.integer "status", default: 0
    t.integer "action_user_id"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_label"
    t.string "friend_label"
    t.index ["user_id"], name: "index_relationships_on_user_id"
  end

  create_table "request_contracts", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "item_id"
    t.decimal "quantity", precision: 10, scale: 5
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "inventory_id"
    t.integer "steps", default: 0
    t.integer "current_step", default: 0
    t.datetime "deleted_at"
    t.datetime "deleted_by"
    t.boolean "archived", default: false
    t.index ["item_id"], name: "index_request_contracts_on_item_id"
    t.index ["user_id"], name: "index_request_contracts_on_user_id"
  end

  create_table "request_list_relationship_statuses", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "relationship_id"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "item_request_id"
    t.index ["item_request_id"], name: "index_request_list_relationship_statuses_on_item_request_id"
    t.index ["relationship_id"], name: "index_request_list_relationship_statuses_on_relationship_id"
  end

  create_table "reviews", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "item_name_id"
    t.bigint "item_id"
    t.integer "producer_id"
    t.integer "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_reviews_on_item_id"
    t.index ["item_name_id"], name: "index_reviews_on_item_name_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "user_category_prices", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "category_id"
    t.decimal "price", precision: 10, scale: 2
    t.string "unit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_user_category_prices_on_category_id"
    t.index ["user_id"], name: "index_user_category_prices_on_user_id"
  end

  create_table "user_groups", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "group_label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_groups_on_user_id"
  end

  create_table "user_relationship_prices", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "friend_id"
    t.bigint "category_id"
    t.bigint "relationship_id"
    t.decimal "price", precision: 10, scale: 2
    t.decimal "receiving_price", precision: 10, scale: 2
    t.string "receiving_price_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_user_relationship_prices_on_category_id"
    t.index ["relationship_id"], name: "index_user_relationship_prices_on_relationship_id"
    t.index ["user_id"], name: "index_user_relationship_prices_on_user_id"
  end

  create_table "user_relationship_request_prices", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "user_id"
    t.integer "friend_id"
    t.bigint "relationship_id"
    t.decimal "price", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "item_request_id"
    t.index ["item_request_id"], name: "index_user_relationship_request_prices_on_item_request_id"
    t.index ["relationship_id"], name: "index_user_relationship_request_prices_on_relationship_id"
    t.index ["user_id"], name: "index_user_relationship_request_prices_on_user_id"
  end

  create_table "users", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "name"
    t.string "nickname"
    t.string "image"
    t.string "email"
    t.text "tokens"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "invitation_limit"
    t.bigint "invited_by_id"
    t.integer "invitations_count", default: 0
    t.string "user_name", default: "", null: false
    t.string "invitation_code"
    t.integer "depth", default: 3
    t.integer "invite_limit", default: 3
    t.string "invited_code"
    t.integer "parent_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitations_count"], name: "index_users_on_invitations_count"
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_id"], name: "index_users_on_invited_by_type_and_invited_by_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["user_name"], name: "index_users_on_user_name", unique: true
  end

  add_foreign_key "inventories", "items"
  add_foreign_key "inventories", "users"
  add_foreign_key "invitations", "users"
  add_foreign_key "item_names", "categories"
  add_foreign_key "item_relatiohships", "items"
  add_foreign_key "item_relatiohships", "relationships"
  add_foreign_key "item_requests", "request_contracts"
  add_foreign_key "item_requests", "users"
  add_foreign_key "items", "categories"
  add_foreign_key "items", "grades"
  add_foreign_key "items", "item_names"
  add_foreign_key "items", "item_units"
  add_foreign_key "items", "users"
  add_foreign_key "relationships", "users"
  add_foreign_key "request_contracts", "items"
  add_foreign_key "request_contracts", "users"
  add_foreign_key "request_list_relationship_statuses", "item_requests"
  add_foreign_key "request_list_relationship_statuses", "relationships"
  add_foreign_key "reviews", "item_names"
  add_foreign_key "reviews", "items"
  add_foreign_key "reviews", "users"
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
