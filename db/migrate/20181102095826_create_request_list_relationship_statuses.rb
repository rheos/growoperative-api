class CreateRequestListRelationshipStatuses < ActiveRecord::Migration[5.2]
  def change
    create_table :request_list_relationship_statuses do |t|
      t.references :request_list, foreign_key: true
      t.references :relationship, foreign_key: true
      t.string     :status

      t.timestamps
    end
  end
end
