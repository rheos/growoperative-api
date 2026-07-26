# frozen_string_literal: true

# Builds the response contract for a balance-moving write.
#
# The TrustlineTransaction is the durable operation buffer, while balance state
# is refetched from FOAF. A response therefore never presents Rails'
# Trustline.current_balance or TrustlineTransaction.balance_after as ledger
# truth.
module Foaf
  class WriteReceipt
    Result = Struct.new(:body, :status, keyword_init: true)

    def self.build(tx_row:, viewer:, message:, serializer: nil)
      new(
        tx_row: tx_row,
        viewer: viewer,
        message: message,
        serializer: serializer
      ).build
    end

    def self.write_state(tx_row)
      tx_row.reload
      return "posted" if tx_row.foaf_posted_at.present?

      tx_row.foaf_write_state.presence || "buffered"
    end

    def self.operation_payload(tx_row)
      state = write_state(tx_row)
      {
        buffer_id: tx_row.id,
        idempotency_key: "growoperative:trustline_transaction:#{tx_row.id}",
        foaf_operation_id: tx_row.foaf_operation_id,
        pending_transfer_id: tx_row.foaf_pending_transfer_id,
        transaction_type: tx_row.transaction_type,
        direction: tx_row.foaf_direction,
        write_state: state,
        write_error: parsed_write_error(tx_row),
        posted_at: tx_row.foaf_posted_at
      }
    end

    def self.parsed_write_error(tx_row)
      return if tx_row.foaf_write_error.blank?

      JSON.parse(tx_row.foaf_write_error)
    rescue JSON::ParserError
      { "error" => tx_row.foaf_write_error }
    end
    private_class_method :parsed_write_error

    def initialize(tx_row:, viewer:, message:, serializer:)
      @tx_row = tx_row
      @viewer = viewer
      @message = message
      @serializer = serializer
    end

    def build
      state = self.class.write_state(@tx_row)
      foaf_state, refetch_error = refetch_foaf_state

      body = {
        message: response_message(state),
        operation: self.class.operation_payload(@tx_row),
        foaf_state: foaf_state
      }
      body[:refetch_error] = refetch_error if refetch_error

      Result.new(body: body, status: http_status(state))
    end

    private

    def refetch_foaf_state
      rows = Foaf::BalanceReader.fetch(@viewer)
      return [nil, "Balance data unavailable — FOAF refetch failed"] if rows.nil?

      row = rows.find { |candidate| candidate[:trustline].id == @tx_row.trustline_id }
      return [nil, "Written trustline was not returned by FOAF"] unless row

      state = @serializer ? @serializer.call(row) : serialize_balance_row(row)
      [state, nil]
    rescue StandardError => e
      Rails.logger.warn(
        "[FOAF WriteReceipt] Refetch failed for tx #{@tx_row.id}: #{e.message}"
      )
      [nil, "Balance data unavailable — FOAF refetch failed"]
    end

    def serialize_balance_row(row)
      trustline = row.fetch(:trustline)
      counterparty = row.fetch(:counterparty)
      balance = row.fetch(:viewer_balance)
      my_limit = row.fetch(:my_credit_limit)

      {
        id: trustline.id,
        other_user: {
          id: counterparty.id,
          name: counterparty.nickname.presence || counterparty.user_name
        },
        my_credit_limit: my_limit,
        their_credit_limit: row.fetch(:their_credit_limit),
        my_available_credit: my_limit - [balance, 0].max,
        current_balance: balance,
        is_active: trustline.is_active,
        established_date: trustline.established_date,
        last_activity: trustline.last_activity,
        notes: trustline.notes
      }
    end

    def response_message(state)
      case state
      when "posted"
        @message
      when "rejected"
        "FOAF rejected the write"
      else
        "Write buffered pending FOAF reconciliation"
      end
    end

    def http_status(state)
      case state
      when "posted"
        :ok
      when "rejected"
        :unprocessable_content
      else
        :accepted
      end
    end
  end
end
