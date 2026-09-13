class ItemRequest < ApplicationRecord
  belongs_to :user
  belongs_to :friend, :class_name => 'User'
  belongs_to :request_contract
  has_one    :inventory, through: :request_contract
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses,dependent: :destroy
  has_one    :order, primary_key: 'order_id', foreign_key: 'id'


  #callbacks

  # UNCONDITIONAL — do NOT add `if: :saved_change_to_status?` or any other guard.
  # perform_accept! saves this same row up to three times inside one transaction,
  # which resets saved-changes tracking and silently defeats such guards. The
  # Resolver is idempotent and a create-time fire is a zero-row no-op (nothing
  # has been published yet), so firing on every commit is safe.
  # :destroy covers hard-deleted hops (edge 5: deleted ItemRequest → :orphaned
  # via resolved_when's subject.destroyed? branch), including the Order-destroy
  # cascade. NOTE: this must stay ONE registration — a separate
  # `after_destroy_commit :resolve_notifications` line registers the same filter
  # on the same :commit chain, and ActiveSupport removes the earlier duplicate,
  # silently killing the create/update hook.
  after_commit :resolve_notifications, on: [:create, :update, :destroy]

  #attribs
  enum status: [ :pending, :accepted, :completed, :cancelled, :reserved ]

  scope :with_inventory_data, -> { joins("INNER JOIN request_contracts ON request_contracts.id = item_requests.request_contract_id INNER JOIN inventories ON inventories.id = request_contracts.inventory_id") }

  # "Accept all" fires concurrent accepts that contend on the same source
  # inventory row and the same seller User row (locked in find_or_create_pending),
  # so Postgres can pick a deadlock victim and roll one back. Retry the victim a few
  # times before surfacing it — see the 2026-06-07 demo 500.
  MAX_ACCEPT_ATTEMPTS = 3
  ACCEPT_RETRY_BACKOFF = 0.05 # seconds, multiplied by attempt number

  def accept_request
    attempts = 0
    begin
      perform_accept!
      true
    rescue Inventory::UnitConversionError => e
      {
        message: "This item is sold by #{e.inventory_unit.unit_name}; you requested #{e.requested_unit.unit_name}. Please pick a matching unit.",
        error: 'unit_conversion_mismatch'
      }
    rescue ActiveRecord::Deadlocked
      attempts += 1
      raise if attempts >= MAX_ACCEPT_ATTEMPTS
      # The rolled-back transaction left self.status mutated to :accepted in memory;
      # reload so the retry reads the true DB state (still :pending) and re-runs the
      # inventory-decrement branch instead of skipping it.
      reload
      sleep(ACCEPT_RETRY_BACKOFF * attempts)
      retry
    end
  end

  def perform_accept!
    ActiveRecord::Base.transaction do
      prev_status = self.status
      self.update!(status: :accepted, accepted_at: DateTime.now)

      # mark next request for sent
      request = ItemRequest.find_by(request_contract_id: self.request_contract_id, user_id: self.friend_id)
      unless request.nil?
        request.sent = 1
        request.save!
      end

      # or request is accepted by the inventory owner
      pending_size = ItemRequest.where("request_contract_id = #{self.request_contract_id} AND status <> 1").size
      if self.step == 1 || pending_size == 0
        self.update!(sent: true) if (prev_status == "reserved" || self.step == 1)
        if(prev_status == "pending")
          source_inventory = self.inventory
          request_unit = requested_item_unit
          reserved_item = reserved_item_for_request(source_inventory, request_unit)
          reserved_quantity = reserved_quantity_for_request(source_inventory.item)

          # reserve new inventory
          reserved = Inventory.new do |m|
            m.item_id = reserved_item.id
            m.user_id = source_inventory.user_id
            m.price = source_inventory.price
            m.quantity = reserved_quantity
            m.ref_id = source_inventory.id #ref_id is pointing to previous inventory, which is needs do be restored
            m.status = :reserved
            m.gallery_map = source_inventory.gallery_map
            m.save!
          end

          # decrease origin inventory quantity
          source_inventory.decrement_for_request!(self.request_contract.quantity, request_unit)

          # update inventory status if all item requests are accepted
          self.request_contract.update!(status: :accepted) if pending_size == 0
          # bind contract to a new reserved inventory and update status
          RequestContract.find_by(id: self.request_contract_id).update!(inventory_id: reserved.id)

          # create or find a pending order with no shipped/completed items
          order = Order.find_or_create_pending(self.user_id, self.friend_id)
          self.update!(order_id: order.id)
        else
          order = Order.find_or_create_pending(self.user_id, self.friend_id)
          self.update!(order_id: order.id)
          self.request_contract.update!(status: :accepted) if pending_size == 0
        end
      end
    end
  end

  def ship (multi = false)
    self.shipped_at = DateTime.now
    self.status = :completed
    # self.order_id = nil if !multi
    self.save!
  end

  def sign (multi = false)
    self.update(signed_at: DateTime.now)
    # change inventory ownership and price
    self.inventory.update(user_id: self.user_id, ref_id: nil, price: self.price)
    # Note: ref_id is disabled because inventory will not be merged with original if contract will be cancelled
  
    # Create or find order if current request isn't last in chain and there are requests with same relation present
    next_request = ItemRequest.find_by(request_contract_id: self.request_contract_id, friend_id: self.user_id)

    if next_request
      order = Order.find_or_create_pending(next_request.user_id, next_request.friend_id)
      next_request.update(order_id: order.id)
    end

    # Update current contract step and finish contract, if all steps are done
    request_contract = self.request_contract

    request_contract.current_step += 1
    if request_contract.current_step == request_contract.steps
      request_contract.status = :completed
      inventory.update(status: :unavailable)
    end

    request_contract.save!
  end

  def calculate_cahin_status
    contract = self.request_contract
    return contract.status if ['accepted', 'completed', 'cancelled'].include?(contract.status)
    if contract.item_requests.where(status: :pending).count > 0
      return 'partially'
    else
      return 'pending'
    end

  end

  def to_json(current_user)
    target_user_id = self.user_id == current_user.id ? self.friend_id : self.user_id
    {
      :id => self.id, 
      :attributes => {
        'quantity' => self.request_contract.quantity, 
        'total-price' => self.price,
        'user-id' => target_user_id,
        'target-user-id' => target_user_id,
        'target-user-name' => ApplicationController.helpers.target_user_name(current_user.id, target_user_id),
        'category-id' => self.inventory.item.category_id,
        'name' => self.inventory.item.name,
        'grade-id' => self.inventory.item.grade_id,
        'item-unit-id' => self.inventory.item.item_unit_id,
        'inventory_id' => self.inventory.id,
        'unit-name' => self.inventory.item.item_unit.item_symbol,
        'item-name-id' => self.inventory.item.item_name_id,
        'date-available' => self.inventory.item.date_available,
        'total-quantity' => self.inventory.quantity,
        'organic' => self.inventory.item.organic,
        'created-at' => self.created_at,
        'sent' => self.user_id == current_user.id,
        'avatars' => self.inventory.avatars_with_item,
        'owner-id' => self.inventory.user_id,
        'producer' => self.inventory.item.producer_id,
        'order' => self.order_id,
        'contract_chain_status' => calculate_cahin_status,
        'unit' => self.request_contract.unit
      }
    }
  end

  private

  def resolve_notifications
    Notifications.resolve!(self)
  end

  def requested_item_unit
    if request_contract.unit.present?
      ItemUnit.find(request_contract.unit.to_i)
    else
      inventory.item.item_unit
    end
  end

  def reserved_quantity_for_request(source_item)
    request_contract.quantity
  end

  def reserved_item_for_request(source_inventory, request_unit)
    source_item = source_inventory.item

    if request_unit.id != source_item.item_unit_id
      # Existing inventory-in-different-unit flow: create a derived item for the reserved copy.
      derived_item_for(source_item, request_unit, source_item.user_id)
    else
      source_item
    end
  end

  def derived_item_for(source_item, item_unit, user_id)
    derived_item = Item.new(source_item.attributes.merge(
      id: nil,
      user_id: user_id,
      item_unit_id: item_unit.id,
      unit: nil,
      created_at: nil,
      updated_at: nil
    ))
    derived_item.avatars = source_item.avatars
    derived_item.with_inventory = true
    derived_item.save!
    derived_item
  end
end
