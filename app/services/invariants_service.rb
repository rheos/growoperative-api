# Data-integrity checks over the current DB state.
#
# Used by GET /v1/debug/invariants and the end-to-end trade test. Every
# check returns its findings as a list of violations; the service collects
# them all (doesn't bail on the first) so a single call can surface multiple
# problems.
#
# Add new checks as private class methods and register them in CHECKS.
#
# Violation shape: { name:, message:, context: {...} }
class InvariantsService
  CHECKS = %i[
    chain_ship_ordering
    chain_sign_ordering
    order_atomicity
    order_membership
    contract_current_step
    orphan_requests
    chain_pricing
  ].freeze

  def self.run
    violations = []
    CHECKS.each do |name|
      begin
        send("check_#{name}", violations)
      rescue => e
        violations << {
          name: name,
          message: "check raised: #{e.class}: #{e.message}",
          context: { backtrace: e.backtrace.first(3) },
        }
      end
    end
    { passed: violations.empty?, count: violations.size, violations: violations }
  end

  # --- Chain ordering ---------------------------------------------------------

  # If step N has shipped, all prior steps in the same contract must also
  # have shipped. Catches atomic-ship dragging a chain step forward.
  def self.check_chain_ship_ordering(violations)
    RequestContract.where.not(status: 'cancelled').includes(:item_requests).find_each do |c|
      irs = c.item_requests.sort_by(&:step)
      earliest_unshipped = nil
      irs.each do |ir|
        if ir.shipped_at.nil? && earliest_unshipped.nil?
          earliest_unshipped = ir.step
        elsif ir.shipped_at && earliest_unshipped
          violations << {
            name: :chain_ship_ordering,
            message: "contract #{c.id} step #{ir.step} is shipped but step #{earliest_unshipped} is not",
            context: {
              contract_id: c.id,
              chain: irs.map { |r| { step: r.step, shipped: !r.shipped_at.nil?, signed: !r.signed_at.nil?, request_id: r.id } },
            },
          }
        end
      end
    end
  end

  # Same rule for sign.
  def self.check_chain_sign_ordering(violations)
    RequestContract.where.not(status: 'cancelled').includes(:item_requests).find_each do |c|
      irs = c.item_requests.sort_by(&:step)
      earliest_unsigned = nil
      irs.each do |ir|
        if ir.signed_at.nil? && earliest_unsigned.nil?
          earliest_unsigned = ir.step
        elsif ir.signed_at && earliest_unsigned
          violations << {
            name: :chain_sign_ordering,
            message: "contract #{c.id} step #{ir.step} is signed but step #{earliest_unsigned} is not",
            context: { contract_id: c.id, request_id: ir.id },
          }
        end
      end
    end
  end

  # --- Order ------------------------------------------------------------------

  # No mixed-ship orders. Either all item_requests on an order are shipped
  # or none are.
  def self.check_order_atomicity(violations)
    Order.includes(:item_requests).find_each do |o|
      next if o.item_requests.empty?
      shipped   = o.item_requests.count { |ir| !ir.shipped_at.nil? }
      unshipped = o.item_requests.count { |ir| ir.shipped_at.nil? }
      next if shipped.zero? || unshipped.zero?
      violations << {
        name: :order_atomicity,
        message: "order #{o.id} has #{shipped} shipped and #{unshipped} unshipped item_requests",
        context: {
          order_id: o.id,
          order_status: o.order_status,
          request_ids: o.item_requests.map { |ir| { id: ir.id, shipped: !ir.shipped_at.nil? } },
        },
      }
    end
  end

  # Every item_request on an order must match the order's buyer-seller pair.
  def self.check_order_membership(violations)
    ItemRequest.where.not(order_id: nil).find_each do |ir|
      o = Order.find_by(id: ir.order_id)
      unless o
        violations << {
          name: :order_membership,
          message: "item_request #{ir.id} references missing order #{ir.order_id}",
          context: { request_id: ir.id, order_id: ir.order_id },
        }
        next
      end
      if ir.user_id.to_s != o.user_id.to_s || ir.friend_id.to_s != o.friend_id.to_s
        violations << {
          name: :order_membership,
          message: "item_request #{ir.id} (user=#{ir.user_id} friend=#{ir.friend_id}) on order #{o.id} (user=#{o.user_id} friend=#{o.friend_id})",
          context: { request_id: ir.id, order_id: o.id },
        }
      end
    end
  end

  # --- Contract ---------------------------------------------------------------

  # current_step increments on each sign. It must equal the number of signed
  # item_requests at all times.
  def self.check_contract_current_step(violations)
    RequestContract.where.not(status: 'cancelled').includes(:item_requests).find_each do |c|
      signed = c.item_requests.count { |ir| !ir.signed_at.nil? }
      next if c.current_step.to_i == signed
      violations << {
        name: :contract_current_step,
        message: "contract #{c.id} current_step=#{c.current_step} but signed_count=#{signed}",
        context: { contract_id: c.id, steps: c.steps, current_step: c.current_step, signed: signed },
      }
    end
  end

  # --- Pricing ----------------------------------------------------------------

  # Each non-anchor hop's stored price must equal the previous hop's stored
  # price compounded by the per-hop markup (UCP / URP / subnet default).
  #
  # Step 1 (the inventory-holder hop) is treated as the anchor and trusted as
  # given — we don't recompute it against inventory.price, because inventories
  # can be re-priced after a contract is created and that drift would produce
  # false positives. Steps 2..N are forward-computed from step 1's stored
  # value: this catches any markup-graph mismatch without depending on the
  # inventory's *current* base price.
  #
  # Skips: cancelled requests, manual-unit contracts (request_contract.unit_id
  # present bypasses the chain calc), single-hop contracts (no math to check),
  # and contracts whose inventory has been deleted.
  def self.check_chain_pricing(violations)
    RequestContract.where.not(status: 'cancelled').includes(:item_requests, :inventory).find_each do |c|
      inv = c.inventory
      next unless inv
      next if c.respond_to?(:unit_id) && c.unit_id.present?

      irs = c.item_requests.sort_by(&:step) # step 1 = inventory-holder hop
      next if irs.size < 2

      running = irs.first.price.to_f

      irs.each_with_index do |ir, i|
        next if i.zero? # anchor; not validated here

        # On an item_request, user_id is the buyer at that hop and friend_id
        # is the seller. The markup graph is keyed seller -> buyer.
        seller_id, buyer_id = ir.friend_id, ir.user_id
        markup = markup_for(seller_id, buyer_id)
        running = markup.apply_to(running)

        next if (ir.price.to_f - running).abs < 0.011 # nickel-rounding tolerance

        violations << {
          name: :chain_pricing,
          message: "contract #{c.id} step #{ir.step}: stored=$#{ir.price.to_f} expected=$#{running} " \
                   "(prev=$#{irs[i - 1].price.to_f} + #{markup.type} #{markup.value})",
          context: {
            contract_id: c.id,
            request_id: ir.id,
            step: ir.step,
            stored_price: ir.price.to_f,
            expected_price: running,
            anchor_price: irs.first.price.to_f,
            previous_step_price: irs[i - 1].price.to_f,
            markup_type: markup.type,
            markup_value: markup.value,
            seller_id: seller_id,
            buyer_id: buyer_id,
            inventory_id: inv.id,
            apply_first_hop_markup: inv.apply_first_hop_markup,
          },
        }
      end
    end
  end

  def self.markup_for(seller_id, buyer_id)
    return Markup.flat(0) if seller_id == buyer_id
    rp = UserRelationshipPrice.find_by(user_id: seller_id, friend_id: buyer_id)
    return Markup.from_record(rp) if rp && rp.price
    ucp = UserCategoryPrice.find_by(user_id: seller_id)
    return Markup.from_record(ucp) if ucp
    cfg = SiteConfig.for(User.find(seller_id).primary_subnet)
    return Markup.new(type: cfg[:default_markup_type], value: cfg[:default_markup]) if cfg
    Markup.flat(Category.first&.default_node_price || 0)
  end

  # Non-cancelled item_requests must have a resolvable contract + inventory.
  def self.check_orphan_requests(violations)
    ItemRequest.where.not(status: 'cancelled').find_each do |ir|
      c = ir.request_contract
      unless c
        violations << {
          name: :orphan_requests,
          message: "item_request #{ir.id} has no request_contract",
          context: { request_id: ir.id },
        }
        next
      end
      unless c.inventory
        violations << {
          name: :orphan_requests,
          message: "request_contract #{c.id} has no inventory",
          context: { contract_id: c.id, request_id: ir.id },
        }
      end
    end
  end
end
