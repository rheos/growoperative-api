class RequestListRelationshipStatus < ApplicationRecord
  belongs_to :item_request
  belongs_to :relationship
end
