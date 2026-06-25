class CreatePushTokens < ActiveRecord::Migration[5.2]
  def change
    create_table :push_tokens do |t|
      t.bigint   :user_id,     null: false
      t.string   :token,       null: false
      t.string   :device_id,   null: false
      t.string   :platform,    null: false
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :push_tokens, :user_id, name: 'index_push_tokens_on_user_id'
    add_index :push_tokens, :token, unique: true, name: 'index_push_tokens_on_token'
    add_index :push_tokens, [:user_id, :device_id], unique: true, name: 'index_push_tokens_on_user_id_and_device_id'
    add_foreign_key :push_tokens, :users
  end
end
