module Api::V1
  class PendingPaymentsController < ApiController
    before_action :set_pending_payment, only: [:confirm, :reject, :destroy, :mark_paid]

    OPEN_STATES = [:pending, :paid_pending_confirmation].freeze

    # GET /v1/pending_payments
    # Returns:
    #   incoming = anything current_user must act on next
    #   outgoing = anything current_user initiated and is waiting on
    def index
      open = PendingPayment.where(status: OPEN_STATES)
                           .where('from_user_id = ? OR to_user_id = ?', current_user.id, current_user.id)
                           .includes(:from_user, :to_user, :trustline)
                           .order(created_at: :desc)

      incoming = open.select { |pp| pp.awaiting_user&.id == current_user.id }
      outgoing = open.reject { |pp| pp.awaiting_user&.id == current_user.id }

      render json: {
        incoming: incoming.map { |pp| serialize(pp) },
        outgoing: outgoing.map { |pp| serialize(pp) }
      }
    end

    # POST /v1/pending_payments
    # Creates either a payment (current_user is payer) or a request
    # (current_user is creditor asking debtor to settle in cash).
    def create
      trustline = current_user.trustlines.find(params[:trustline_id])
      other = trustline.other_user(current_user)
      kind = params[:kind] == 'request' ? 'request' : 'payment'

      pp = PendingPayment.new(
        from_user: current_user,
        to_user: other,
        trustline: trustline,
        amount: params[:amount],
        description: params[:description],
        kind: kind
      )

      if pp.save
        Notifications.publish!(
          event:      kind == 'request' ? :payment_request_created : :pending_payment_created,
          actor:      current_user,
          recipients: [other],
          resource:   pp
        )
        render json: serialize(pp), status: :created
      else
        render json: { errors: pp.errors.full_messages }, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotFound
      render json: { errors: ['Trustline not found'] }, status: :not_found
    end

    # PUT /v1/pending_payments/:id/mark_paid
    # Debtor on a request says "I paid in cash". Notifies creditor for receipt
    # confirmation. Trustline does not change yet.
    def mark_paid
      unless @pending_payment.request? && @pending_payment.to_user_id == current_user.id
        return render json: { errors: ['Only the debtor on a request can mark it paid'] }, status: :forbidden
      end

      begin
        @pending_payment.mark_paid!
        Notifications.publish!(
          event:      :payment_request_paid,
          actor:      current_user,
          recipients: [@pending_payment.from_user],
          resource:   @pending_payment
        )
        render json: { message: 'Marked as paid', pending_payment: serialize(@pending_payment) }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_content
      end
    end

    # PUT /v1/pending_payments/:id/confirm
    # Confirms receipt and executes the trustline settlement. Authorization
    # depends on kind/state — handled by PendingPayment#awaiting_user.
    def confirm
      unless @pending_payment.awaiting_user&.id == current_user.id
        return render json: { errors: ['Not your turn to confirm'] }, status: :forbidden
      end

      begin
        new_balance = @pending_payment.confirm!
        # FYI to the payer (the counterparty of the confirmer) that receipt was confirmed
        # and the trustline balance settled.
        payer = current_user.id == @pending_payment.from_user_id ? @pending_payment.to_user : @pending_payment.from_user
        if payer
          Notifications.publish!(event: :payment_received, actor: current_user,
                                 recipients: [payer], resource: @pending_payment)
        end
        render json: {
          message: 'Payment confirmed',
          new_balance: new_balance,
          pending_payment: serialize(@pending_payment)
        }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_content
      end
    end

    # PUT /v1/pending_payments/:id/reject
    # Either side can reject while the record is still open.
    def reject
      unless @pending_payment.awaiting_user&.id == current_user.id
        return render json: { errors: ['Not your turn to reject'] }, status: :forbidden
      end

      begin
        @pending_payment.reject!(reason: params[:reason])
        render json: { message: 'Payment rejected', pending_payment: serialize(@pending_payment) }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_content
      end
    end

    # DELETE /v1/pending_payments/:id
    # Initiator cancels while still open.
    def destroy
      unless @pending_payment.initiator_id == current_user.id
        return render json: { errors: ['Only the initiator can cancel'] }, status: :forbidden
      end

      begin
        @pending_payment.cancel!
        render json: { message: 'Payment cancelled' }
      rescue => e
        render json: { errors: [e.message] }, status: :unprocessable_content
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
        kind: pp.kind,
        from_user: { id: pp.from_user.id, name: pp.from_user.user_name },
        to_user: { id: pp.to_user.id, name: pp.to_user.user_name },
        trustline_id: pp.trustline_id,
        amount: pp.amount.to_f,
        description: pp.description,
        status: pp.status,
        paid_at: pp.paid_at,
        created_at: pp.created_at
      }
    end
  end
end
