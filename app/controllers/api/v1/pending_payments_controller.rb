module Api::V1
  class PendingPaymentsController < ApiController
    before_action :set_pending_payment, only: [:confirm, :reject, :destroy]

    # GET /v1/pending_payments
    # Returns incoming and outgoing pending payments for current user
    def index
      incoming = PendingPayment.where(to_user: current_user, status: :pending)
                               .includes(:from_user, :to_user, :trustline)
                               .order(created_at: :desc)

      outgoing = PendingPayment.where(from_user: current_user, status: :pending)
                               .includes(:from_user, :to_user, :trustline)
                               .order(created_at: :desc)

      render json: {
        incoming: incoming.map { |pp| serialize(pp) },
        outgoing: outgoing.map { |pp| serialize(pp) }
      }
    end

    # POST /v1/pending_payments
    # Payer creates a pending payment for the payee to confirm
    def create
      trustline = current_user.trustlines.find(params[:trustline_id])
      to_user = trustline.other_user(current_user)

      pp = PendingPayment.new(
        from_user: current_user,
        to_user: to_user,
        trustline: trustline,
        amount: params[:amount],
        description: params[:description]
      )

      if pp.save
        Notifications.publish!(
          event:      :pending_payment_created,
          actor:      current_user,
          recipients: [to_user],
          resource:   pp
        )
        render json: serialize(pp), status: :created
      else
        render json: { errors: pp.errors.full_messages }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { errors: ['Trustline not found'] }, status: :not_found
    end

    # PUT /v1/pending_payments/:id/confirm
    # Payee confirms — executes the payment on the trustline
    def confirm
      unless @pending_payment.to_user_id == current_user.id
        return render json: { errors: ['Only the recipient can confirm'] }, status: :forbidden
      end

      begin
        new_balance = @pending_payment.confirm!
        render json: {
          message: 'Payment confirmed',
          new_balance: new_balance,
          pending_payment: serialize(@pending_payment)
        }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end
    end

    # PUT /v1/pending_payments/:id/reject
    # Payee rejects with optional reason
    def reject
      unless @pending_payment.to_user_id == current_user.id
        return render json: { errors: ['Only the recipient can reject'] }, status: :forbidden
      end

      begin
        @pending_payment.reject!(reason: params[:reason])
        render json: {
          message: 'Payment rejected',
          pending_payment: serialize(@pending_payment)
        }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end
    end

    # DELETE /v1/pending_payments/:id
    # Payer cancels while still pending
    def destroy
      unless @pending_payment.from_user_id == current_user.id
        return render json: { errors: ['Only the sender can cancel'] }, status: :forbidden
      end

      begin
        @pending_payment.cancel!
        render json: { message: 'Payment cancelled' }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end
    end

    private

    def set_pending_payment
      @pending_payment = PendingPayment.find(params[:id])
      unless @pending_payment.from_user_id == current_user.id || @pending_payment.to_user_id == current_user.id
        render json: { errors: ['Not authorized'] }, status: :forbidden
      end
    rescue ActiveRecord::RecordNotFound
      render json: { errors: ['Pending payment not found'] }, status: :not_found
    end

    def serialize(pp)
      {
        id: pp.id,
        from_user: { id: pp.from_user.id, name: pp.from_user.user_name },
        to_user: { id: pp.to_user.id, name: pp.to_user.user_name },
        trustline_id: pp.trustline_id,
        amount: pp.amount.to_f,
        description: pp.description,
        status: pp.status,
        created_at: pp.created_at
      }
    end
  end
end
