# frozen_string_literal: true

# Response contract for a trustline-limit publication. The durable
# FoafOutboxEntry is the operation record; displayed balance/limit state is
# always refetched from FOAF.
module Foaf
  class LimitWriteReceipt
    Result = Struct.new(:body, :status, keyword_init: true)

    def self.build(entry:, trustline:, viewer:, message:, success_status:, serializer:)
      new(
        entry: entry,
        trustline: trustline,
        viewer: viewer,
        message: message,
        success_status: success_status,
        serializer: serializer
      ).build
    end

    def initialize(entry:, trustline:, viewer:, message:, success_status:, serializer:)
      @entry = entry
      @trustline = trustline
      @viewer = viewer
      @message = message
      @success_status = success_status
      @serializer = serializer
    end

    def build
      state = write_state
      foaf_state, refetch_error = refetch_foaf_state
      body = {
        message: response_message(state),
        trustline_id: @trustline.id,
        operation: operation_payload(state),
        foaf_state: foaf_state
      }
      body[:refetch_error] = refetch_error if refetch_error

      Result.new(body: body, status: http_status(state))
    end

    private

    def write_state
      return "unchanged" unless @entry

      @entry.reload
      return "posted" if @entry.foaf_posted_at.present?

      @entry.foaf_write_state.presence || "buffered"
    end

    def operation_payload(state)
      {
        buffer_id: @entry&.id,
        operation_type: FoafOutboxEntry::TRUSTLINE_UPDATE,
        write_state: state,
        write_error: parsed_write_error,
        posted_at: @entry&.foaf_posted_at
      }
    end

    def parsed_write_error
      return if @entry&.foaf_write_error.blank?

      JSON.parse(@entry.foaf_write_error)
    rescue JSON::ParserError
      { "error" => @entry.foaf_write_error }
    end

    def refetch_foaf_state
      rows = Foaf::BalanceReader.fetch(@viewer)
      return [nil, "Balance data unavailable — FOAF refetch failed"] if rows.nil?

      row = rows.find { |candidate| candidate[:trustline].id == @trustline.id }
      return [nil, "Written trustline was not returned by FOAF"] unless row

      [@serializer.call(row), nil]
    rescue StandardError => e
      Rails.logger.warn(
        "[FOAF LimitWriteReceipt] Refetch failed for trustline #{@trustline.id}: #{e.message}"
      )
      [nil, "Balance data unavailable — FOAF refetch failed"]
    end

    def response_message(state)
      case state
      when "posted", "unchanged"
        @message
      when "rejected"
        "FOAF rejected the trustline update"
      else
        "Trustline update buffered pending FOAF reconciliation"
      end
    end

    def http_status(state)
      case state
      when "posted", "unchanged"
        @success_status
      when "rejected"
        :unprocessable_content
      else
        :accepted
      end
    end
  end
end
