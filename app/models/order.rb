class Order < ApplicationRecord
  has_many :item_requests, primary_key: 'id', foreign_key: 'order_id'

  enum order_status: [ :pending, :shipped, :signed ]

  def remove_request (id)
    # self.item_requests.find(id)
  end

  def apply_action (action, user_id)
    # binding.pry
    case action[:action_name]
    when 'sign'
      # binding.pry
      return false if (user_id.to_s != self.user_id || self.order_status != "shipped")
      self.item_requests.each do |item_request|
        item_request.sign if !item_request.signed_at
      end
      self.update(signed_on: DateTime.now, order_status: :signed)
    when 'ship'
      return false if (user_id.to_s != self.friend_id || self.order_status == "shipped")
      self.item_requests.each do |item_request|
        item_request.ship if !item_request.shipped_at
      end
      self.update(shipped_on: DateTime.now, order_status: :shipped)
    when 'remove_item'
      item = self.item_requests.find_by(id: action[:request_id])
      return false if !item || item.friend_id.to_s != user_id.to_s
      item.update(order_id: nil)
    else
      return false
    end
  end
end
