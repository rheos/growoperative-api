class CreatePushTokens < ActiveRecord::Migration[5.2]
  def change
    unless table_exists?(:push_tokens)
      create_table :push_tokens do |t|
        t.bigint   :user_id,     null: false
        t.string   :token,       null: false
        t.string   :device_id,   null: false
        t.string   :platform,    null: false
        t.datetime :last_seen_at
        t.timestamps
      end
    end

    add_index :push_tokens, :user_id, name: 'index_push_tokens_on_user_id' unless index_exists?(:push_tokens, :user_id, name: 'index_push_tokens_on_user_id')
    add_index :push_tokens, :token, unique: true, name: 'index_push_tokens_on_token' unless index_exists?(:push_tokens, :token, name: 'index_push_tokens_on_token')
    unless index_exists?(:push_tokens, [:user_id, :device_id], name: 'index_push_tokens_on_user_id_and_device_id')
      add_index :push_tokens, [:user_id, :device_id], unique: true, name: 'index_push_tokens_on_user_id_and_device_id'
    end
    add_foreign_key :push_tokens, :users unless foreign_key_exists?(:push_tokens, :users)
  end
end
