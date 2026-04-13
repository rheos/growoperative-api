class CreateNotifications < ActiveRecord::Migration[5.2]
  def change
    create_table :notifications do |t|
      t.bigint   :recipient_id,      null: false
      t.bigint   :actor_id
      t.string   :notification_type,  null: false
      t.text     :message,            null: false
      t.string   :actor_name
      t.string   :actor_avatar_url
      t.string   :target_type
      t.bigint   :target_id
      t.string   :target_screen
      t.json     :metadata
      t.boolean  :read,               null: false, default: false
      t.datetime :read_at
      t.timestamps
    end

    add_index :notifications, [:recipient_id, :read, :created_at], name: 'index_notifications_inbox'
    add_index :notifications, [:recipient_id, :created_at],        name: 'index_notifications_timeline'
    add_foreign_key :notifications, :users, column: :recipient_id
    add_foreign_key :notifications, :users, column: :actor_id
  end
end
