class AddFoafSeedPhraseToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :foaf_seed_phrase, :text
  end
end
