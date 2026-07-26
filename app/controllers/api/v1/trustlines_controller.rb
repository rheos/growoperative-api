# Trustlines API Controller - Mutual Credit System Management
#
# Provides REST API endpoints for managing trustlines (credit relationships)
# and processing payments through the mutual credit network.
#
# Authentication: All endpoints require authenticated user
# Authorization: Users can only manage their own trustlines
#
# Core Endpoints:
# - CRUD operations for trustlines
# - Payment processing (direct and multi-hop)
# - Path finding for network payments
# - User credit summaries and transaction history
#
# Payment Flow Example:
#   1. GET /summary - Check available credit
#   2. POST /find_path - Find route to recipient
#   3. POST /execute_path_payment - Execute the payment
#   4. GET /summary - Verify updated balances

class Api::V1::TrustlinesController < Api::V1::ApiController
  # Auth is inherited from ApiController (before_action :authenticate!)
  before_action :set_trustline, only: [:show, :update, :destroy]
  before_action :set_other_user, only: [:create]
  
  # === CRUD OPERATIONS ===
  
  # Lists all active trustlines for the current user
  # GET /api/v1/trustlines
  #
  # Balance and credit limits come from FOAF (authoritative). Rails supplies
  # non-balance metadata (id, established_date, notes, is_active). See
  # docs/claude/plans/todo/21-retire-rails-trustline-balances.md for the cutover.
  def index
    rows = Foaf::BalanceReader.fetch(current_user)
    return render json: rows.map { |row| serialize_balance_row(row) } unless rows.nil?

    # FOAF is authoritative for balances, so a real-production FOAF outage must
    # fail loud rather than silently serve possibly-diverged Rails balances. But
    # envs that run NO FOAF service (local dev; the beta backend) should fall back
    # to Rails' own trustline data so the screen is usable instead of 503ing.
    # Gate: any non-production env, OR an env that explicitly opts in via
    # FOAF_BALANCE_FALLBACK=true (beta runs RAILS_ENV=production but has no FOAF).
    fallback_allowed = !Rails.env.production? || ENV['FOAF_BALANCE_FALLBACK'] == 'true'
    return render_foaf_unavailable unless fallback_allowed
    render json: current_user.trustlines.active.map { |tl| serialize_trustline(tl) }
  end

  # Shows details of a specific trustline
  # GET /api/v1/trustlines/:id
  def show
    rows = Foaf::BalanceReader.fetch(current_user)
    return render_foaf_unavailable if rows.nil?
    row = rows.find { |r| r[:trustline].id == @trustline.id }
    if row
      render json: serialize_balance_row(row)
    else
      render json: { errors: ['Trustline not found in FOAF'] }, status: :service_unavailable
    end
  end
  
  # Creates a new trustline between current user and another user
  # POST /api/v1/trustlines
  #
  # Parameters:
  # - other_user_id: ID of user to establish trustline with
  # - my_credit_limit: Credit limit I extend to them
  # - their_credit_limit: Credit limit they extend to me
  # - notes: Optional notes about the relationship
  #
  # Returns: Created trustline object or validation errors
  def create
    # Frontend sends a single :credit_limit (the creator's outgoing limit);
    # the older API expected :my_credit_limit / :their_credit_limit. Accept both.
    my_limit = params[:my_credit_limit] || params[:credit_limit] || 0
    their_limit = params[:their_credit_limit] || 0

    # establish_trustline_with returns the existing line if one is already there;
    # only notify the counterparty when this call actually opens a NEW trustline.
    already_existed = current_user.trustline_with(@other_user).present?
    @trustline = current_user.establish_trustline_with(
      @other_user,
      my_credit_limit: my_limit,
      their_credit_limit: their_limit,
      notes: params[:notes]
    )

    if @trustline.persisted?
      Foaf::LedgerHooks.after_trustline_save(@trustline, current_user)
      if !already_existed && @other_user
        Notifications.publish!(event: :trustline_created, actor: current_user,
                               recipients: [@other_user], resource: @trustline)
      end
      render json: serialize_trustline(@trustline), status: :created
    else
      render json: { errors: @trustline.errors.full_messages }, status: :unprocessable_content
    end
  end
  
  # Updates credit limits or notes for an existing trustline
  # PATCH/PUT /api/v1/trustlines/:id
  #
  # Parameters:
  # - credit_limit_a_to_b: New limit from user A to user B
  # - credit_limit_b_to_a: New limit from user B to user A
  # - notes: Updated relationship notes
  # - is_active: Activate/deactivate the trustline
  #
  # Returns: Updated trustline object or validation errors
  def update
    if @trustline.update(trustline_params)
      Foaf::LedgerHooks.after_trustline_save(@trustline, current_user)
      render json: serialize_trustline(@trustline)
    else
      render json: { errors: @trustline.errors.full_messages }, status: :unprocessable_content
    end
  end
  
  # Deactivates a trustline (soft delete)
  # DELETE /api/v1/trustlines/:id
  #
  # Note: Trustlines are deactivated rather than deleted to preserve
  # transaction history and audit trail
  #
  # Returns: Success message or error
  def destroy
    if @trustline.update(is_active: false)
      render json: { message: 'Trustline deactivated successfully' }
    else
      render json: { errors: ['Failed to deactivate trustline'] }, status: :unprocessable_content
    end
  end
  
  # === FINANCIAL SUMMARY ===
  
  # Provides comprehensive financial summary for current user
  # GET /api/v1/trustlines/summary
  #
  # Returns:
  # - total_trustlines: Number of active trustlines
  # - total_credit_owed: Amount user owes to others
  # - total_credit_owed_to_me: Amount others owe to user
  # - net_credit_position: Net position (positive = creditor)
  # - available_credit: Total credit available for spending
  # - recent_transactions: Last 5 transactions initiated by user
  def summary
    foaf_summary = Foaf::BalanceSummary.fetch(current_user)
    return render_foaf_unavailable if foaf_summary.nil?

    summary_data = foaf_summary.transform_values do |value|
      value.is_a?(BigDecimal) ? value.to_f : value
    end.merge(
      recent_transactions: current_user.initiated_trustline_transactions
                                      .includes(:initiated_by, :order)
                                      .recent
                                      .limit(5)
                                      .map { |tx| serialize_transaction(tx) }
    )
    
    render json: summary_data
  end
  
  # === PAYMENT PROCESSING ===
  
  # Processes a direct payment through a specific trustline
  # POST /api/v1/trustlines/:id/payment
  #
  # Parameters:
  # - amount: Payment amount (must be positive)
  # - description: Optional payment description
  # - originating_request_id: Optional ItemRequest that triggered payment
  #
  # Returns:
  # - message: Success confirmation
  # - new_balance: Updated trustline balance
  # - trustline: Updated trustline object
  #
  # Errors: Insufficient credit, invalid amount, or processing failure
  def payment
    @trustline = current_user.trustlines.find(params[:id])
    amount = params[:amount].to_f
    description = params[:description]
    to_user = @trustline.other_user(current_user)
    
    if @trustline.can_handle_payment?(amount, current_user)
      begin
        new_balance = @trustline.process_payment!(
          amount,
          current_user,
          to_user,
          description: description,
          originating_request: params[:originating_request_id] ? 
                              ItemRequest.find(params[:originating_request_id]) : nil
        )
        
        render json: {
          message: 'Payment processed successfully',
          new_balance: new_balance,
          trustline: serialize_trustline(@trustline.reload)
        }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_content
      end
    else
      render json: { errors: ['Insufficient credit limit'] }, status: :unprocessable_content
    end
  end
  
  # === IMMEDIATE BALANCE OPERATIONS ===

  # Records a self-declared debt ("I owe them X")
  # POST /api/v1/trustlines/:id/record_debt
  #
  # The current user voluntarily takes on liability. No confirmation needed
  # from the other party since this benefits them.
  #
  # Parameters:
  # - amount: Debt amount (must be positive)
  # - description: Optional description
  #
  # Returns: Updated trustline with new balance
  def record_debt
    @trustline = current_user.trustlines.find(params[:id])
    amount = params[:amount].to_f
    to_user = @trustline.other_user(current_user)

    if amount <= 0
      return render json: { errors: ['Amount must be greater than zero'] }, status: :unprocessable_content
    end

    # The Rails commit doesn't enforce the limit (force_capacity below), but the
    # FOAF mirror does — an over-limit debt transfer is rejected by FOAF and the
    # balance silently reverts on the next FOAF-sourced read. When the user has
    # explicitly consented to raising their own limit to cover the debt, bump
    # the current user's credit-limit side and mirror it to FOAF *first* so the
    # subsequent debt transfer fits within the (now larger) creditline.
    raise_to = params[:raise_limit_to].to_f
    if raise_to > @trustline.credit_limit_for(current_user).to_f
      if current_user.id == @trustline.user_a_id
        @trustline.update!(credit_limit_a_to_b: raise_to)
      else
        @trustline.update!(credit_limit_b_to_a: raise_to)
      end
      Foaf::LedgerHooks.after_trustline_save(@trustline, current_user)
    end

    # No credit-limit check: voluntary self-adverse declaration. The user is
    # accepting the obligation themselves, so the limit doesn't apply.
    begin
      new_balance = @trustline.process_payment!(
        amount,
        current_user,
        to_user,
        description: params[:description] || "Debt recorded by #{current_user.user_name}",
        force_capacity: true,
        operation: "adjustment"
      )

      # Mark as adjustment so audit trail distinguishes from order settlements
      @trustline.trustline_transactions.last.update!(transaction_type: 'adjustment')

      render json: {
        message: 'Debt recorded',
        new_balance: new_balance,
        trustline: serialize_trustline(@trustline.reload)
      }
    rescue => e
      render json: { errors: [e.message] }, status: :unprocessable_content
    end
  end

  # Records a receipt acknowledgment ("I received X from them")
  # POST /api/v1/trustlines/:id/record_receipt
  #
  # The current user acknowledges receiving value from the other party,
  # reducing the other party's debt. No confirmation needed since this
  # benefits the other party.
  #
  # Parameters:
  # - amount: Receipt amount (must be positive)
  # - description: Optional description
  #
  # Returns: Updated trustline with new balance
  def record_receipt
    @trustline = current_user.trustlines.find(params[:id])
    amount = params[:amount].to_f
    from_user = @trustline.other_user(current_user)

    if amount <= 0
      return render json: { errors: ['Amount must be greater than zero'] }, status: :unprocessable_content
    end

    # Settlement direction: from_user's debt to current_user decreases.
    # No credit-limit check needed — settlement only reduces debt.
    begin
      new_balance = @trustline.settle_payment!(
        amount,
        from_user,
        current_user,
        description: params[:description] || "Receipt acknowledged by #{current_user.user_name}",
        operation: "adjustment"
      )

      # Mark as adjustment so audit trail distinguishes from order settlements
      @trustline.trustline_transactions.last.update!(transaction_type: 'adjustment')

      render json: {
        message: 'Receipt recorded',
        new_balance: new_balance,
        trustline: serialize_trustline(@trustline.reload)
      }
    rescue => e
      render json: { errors: [e.message] }, status: :unprocessable_content
    end
  end

  # === NETWORK PAYMENT ROUTING ===
  
  # Finds a payment path through the trustline network
  # POST /api/v1/trustlines/find_path
  #
  # Parameters:
  # - to_user_id: Destination user ID
  # - amount: Payment amount to route
  # - max_hops: Maximum number of intermediate users (default: 5)
  #
  # Returns:
  # - path_found: Boolean indicating if path exists
  # - path: Array of user objects in payment route
  # - path_length: Number of hops (trustlines) in path
  # - estimated_cost: Total cost (may include fees in future)
  #
  # Use Case: Check if payment is possible before attempting execution
  def find_path
    to_user = User.find(params[:to_user_id])
    amount = params[:amount].to_f
    max_hops = params[:max_hops] || 5
    
    path = Trustline.find_payment_path(current_user, to_user, amount, max_hops: max_hops)
    
    if path
      render json: {
        path_found: true,
        path: path.map { |user| { id: user.id, name: display_name_for(user) } },
        path_length: path.length - 1,  # Number of hops
        estimated_cost: amount  # In a real system, might include fees
      }
    else
      render json: {
        path_found: false,
        message: 'No payment path found within specified constraints'
      }
    end
  end
  
  # Executes a multi-hop payment through the trustline network
  # POST /api/v1/trustlines/execute_path_payment
  #
  # Parameters:
  # - to_user_id: Destination user ID
  # - amount: Payment amount
  # - description: Payment description
  # - max_hops: Maximum hops to allow (default: 5)
  # - originating_request_id: Optional ItemRequest ID
  #
  # Process:
  # 1. Finds optimal payment path using breadth-first search
  # 2. Validates all trustlines in path can handle the amount
  # 3. Executes atomic transaction across all trustlines
  # 4. Records transaction history for each hop
  #
  # Returns: Success confirmation with path details
  # Errors: No path found, insufficient credit, or transaction failure
  def execute_path_payment
    to_user = User.find(params[:to_user_id])
    amount = params[:amount].to_f
    description = params[:description]
    max_hops = params[:max_hops] || 5
    
    path = Trustline.find_payment_path(current_user, to_user, amount, max_hops: max_hops)
    
    if path
      begin
        result = Trustline.execute_payment_path(
          path, 
          amount, 
          description: description,
          originating_request: params[:originating_request_id] ?
                              ItemRequest.find(params[:originating_request_id]) : nil
        )
        
        if result
          render json: {
            message: 'Path payment executed successfully',
            path: path.map { |user| { id: user.id, name: display_name_for(user) } },
            amount: amount
          }
        else
          render json: { errors: ['Path payment execution failed'] }, status: :unprocessable_content
        end
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_content
      end
    else
      render json: { errors: ['No payment path found'] }, status: :unprocessable_content
    end
  end
  
  private

  # === HELPER METHODS ===
  
  # Finds and sets trustline for member actions
  # Ensures user can only access their own trustlines
  def set_trustline
    @trustline = current_user.trustlines.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ['Trustline not found'] }, status: :not_found
  end
  
  # Finds and sets other user for trustline creation.
  # Accepts :other_user_id (legacy) or :user_id (new app).
  def set_other_user
    other_id = params[:other_user_id] || params[:user_id]
    @other_user = User.find(other_id)
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ['User not found'] }, status: :not_found
  end
  
  # Strong parameters for trustline updates
  def trustline_params
    params.permit(:credit_limit_a_to_b, :credit_limit_b_to_a, :notes, :is_active)
  end
  
  # === SERIALIZATION METHODS ===

  def render_foaf_unavailable
    render json: { errors: ['Balance data unavailable — FOAF is unreachable'] }, status: :service_unavailable
  end

  # Serializes a Foaf::BalanceReader row — balance/limits come from FOAF, the
  # rest from the joined Rails Trustline. Output shape matches serialize_trustline
  # so frontend doesn't need to change.
  def serialize_balance_row(row)
    trustline = row[:trustline]
    counterparty = row[:counterparty]
    balance = row[:viewer_balance]
    my_limit = row[:my_credit_limit]

    {
      id: trustline.id,
      other_user: {
        id: counterparty.id,
        name: display_name_for(counterparty)
      },
      my_credit_limit: my_limit,
      their_credit_limit: row[:their_credit_limit],
      my_available_credit: my_limit - [balance, 0].max,
      current_balance: balance,
      is_active: trustline.is_active,
      established_date: trustline.established_date,
      last_activity: trustline.last_activity,
      notes: trustline.notes
    }
  end

  # Serializes trustline object from current user's perspective
  # @param trustline [Trustline] - The trustline to serialize
  # @return [Hash] - JSON-ready hash with trustline data
  def serialize_trustline(trustline)
    other_user = trustline.other_user(current_user)
    
    {
      id: trustline.id,
      other_user: {
        id: other_user.id,
        name: display_name_for(other_user)
      },
      my_credit_limit: trustline.credit_limit_for(current_user).to_f,
      their_credit_limit: trustline.credit_limit_for(other_user).to_f,
      my_available_credit: trustline.available_credit_for(current_user).to_f,
      current_balance: trustline.balance_for(current_user).to_f,
      is_active: trustline.is_active,
      established_date: trustline.established_date,
      last_activity: trustline.last_activity,
      notes: trustline.notes
    }
  end
  
  # Serializes transaction object for API responses
  # @param transaction [TrustlineTransaction] - The transaction to serialize
  # @return [Hash] - JSON-ready hash with transaction data
  def serialize_transaction(transaction)
    {
      id: transaction.id,
      amount: transaction.amount.to_f,
      description: transaction.description,
      transaction_type: transaction.transaction_type,
      created_at: transaction.created_at,
      balance_after: transaction.balance_after.to_f,
      is_reversed: transaction.is_reversed,
      initiated_by_id: transaction.initiated_by_id,
      initiated_by_name: transaction.initiated_by && display_name_for(transaction.initiated_by),
      order_id: transaction.order_id,
      order_label: transaction.order&.order_label,
      originating_request_id: transaction.originating_request_id,
      path_info: transaction.path_info
    }
  end

  def display_name_for(user)
    return nil unless user
    return user.user_name if user.id == current_user.id

    relation = Relationship.where(
      'user_id IN (?) AND friend_id IN (?)',
      [current_user.id, user.id],
      [current_user.id, user.id]
    ).first

    if relation&.user_id == current_user.id && relation.user_label.present?
      relation.user_label
    elsif relation&.friend_id == current_user.id && relation.friend_label.present?
      relation.friend_label
    else
      user.nickname.presence || user.user_name
    end
  end
end
