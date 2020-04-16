class ItemRelationship < ApplicationRecord
  belongs_to :item
  belongs_to :relationship
end
