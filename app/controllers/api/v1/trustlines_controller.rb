class Api::V1::TrustlinesController < Api::V1::ApiController
  before_action :authenticate_user!
  before_action :set_trustline, only: [:show, :update, :destroy]
  before_action :set_other_user, only: [:create]
  
  # GET /api/v1/trustlines
  def index
    @trustlines = current_user.trustlines.active.includes(:user_a, :user_b)
    
    render json: @trustlines.map { |trustline| serialize_trustline(trustline) }
  end
  
  # GET /api/v1/trustlines/:id
  def show
    render json: serialize_trustline(@trustline)
  end
  
  # POST /api/v1/trustlines
  def create
    @trustline = current_user.establish_trustline_with(
      @other_user,
      my_credit_limit: params[:my_credit_limit] || 0,
      their_credit_limit: params[:their_credit_limit] || 0,
      notes: params[:notes]
    )
    
    if @trustline.persisted?
      render json: serialize_trustline(@trustline), status: :created
    else
      render json: { errors: @trustline.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # PATCH/PUT /api/v1/trustlines/:id
  def update
    if @trustline.update(trustline_params)
      render json: serialize_trustline(@trustline)
    else
      render json: { errors: @trustline.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # DELETE /api/v1/trustlines/:id
  def destroy
    if @trustline.update(is_active: false)
      render json: { message: 'Trustline deactivated successfully' }
    else
      render json: { errors: ['Failed to deactivate trustline'] }, status: :unprocessable_entity
    end
  end
  
  # GET /api/v1/trustlines/summary
  def summary
    summary_data = {
      total_trustlines: current_user.active_trustlines.count,
      total_credit_owed: current_user.total_credit_owed,
      total_credit_owed_to_me: current_user.total_credit_owed_to_me,
      net_credit_position: current_user.net_credit_position,
      available_credit: current_user.available_credit_total,
      recent_transactions: current_user.initiated_trustline_transactions
                                      .recent
                                      .limit(5)
                                      .map { |tx| serialize_transaction(tx) }
    }
    
    render json: summary_data
  end
  
  # POST /api/v1/trustlines/:id/payment
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
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end
    else
      render json: { errors: ['Insufficient credit limit'] }, status: :unprocessable_entity
    end
  end
  
  # POST /api/v1/trustlines/find_path
  def find_path
    to_user = User.find(params[:to_user_id])
    amount = params[:amount].to_f
    max_hops = params[:max_hops] || 5
    
    path = Trustline.find_payment_path(current_user, to_user, amount, max_hops: max_hops)
    
    if path
      render json: {
        path_found: true,
        path: path.map { |user| { id: user.id, name: user.user_name } },
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
  
  # POST /api/v1/trustlines/execute_path_payment
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
            path: path.map { |user| { id: user.id, name: user.user_name } },
            amount: amount
          }
        else
          render json: { errors: ['Path payment execution failed'] }, status: :unprocessable_entity
        end
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end
    else
      render json: { errors: ['No payment path found'] }, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_trustline
    @trustline = current_user.trustlines.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ['Trustline not found'] }, status: :not_found
  end
  
  def set_other_user
    @other_user = User.find(params[:other_user_id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ['User not found'] }, status: :not_found
  end
  
  def trustline_params
    params.permit(:credit_limit_a_to_b, :credit_limit_b_to_a, :notes, :is_active)
  end
  
  def serialize_trustline(trustline)
    other_user = trustline.other_user(current_user)
    
    {
      id: trustline.id,
      other_user: {
        id: other_user.id,
        name: other_user.user_name
      },
      my_credit_limit: trustline.credit_limit_for(current_user),
      their_credit_limit: trustline.credit_limit_for(other_user),
      my_available_credit: trustline.available_credit_for(current_user),
      current_balance: trustline.balance_for(current_user),
      is_active: trustline.is_active,
      established_date: trustline.established_date,
      last_activity: trustline.last_activity,
      notes: trustline.notes
    }
  end
  
  def serialize_transaction(transaction)
    {
      id: transaction.id,
      amount: transaction.amount,
      description: transaction.description,
      transaction_type: transaction.transaction_type,
      created_at: transaction.created_at,
      balance_after: transaction.balance_after,
      is_reversed: transaction.is_reversed
    }
  end
end 