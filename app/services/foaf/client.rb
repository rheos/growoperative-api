# frozen_string_literal: true

# HTTP client for the FOAF protocol API.
# All FOAF communication goes through this class.

require "net/http"
require "json"
require "uri"

module Foaf
  class Client
    def initialize(base_url: Foaf::Config.api_url, shared_client: nil)
      @base_url = base_url
      @shared_client = shared_client || Foaf::LedgerClient.new(
        base_url: base_url,
        logger: Rails.logger,
        signature_provider: method(:sign_shared_payload)
      )
    end

    # === KEYPAIR ===

    def generate_keypair
      compare_read(:generate_keypair, legacy: -> { post("/api/v1/keypair") }) do
        @shared_client.generate_keypair
      end
    end

    # === NETWORKS ===

    def networks
      compare_read(:networks, legacy: -> { get("/api/v1/networks") }) do
        @shared_client.networks
      end
    end

    # === TRUSTLINES ===

    def update_trustline(network_address:, creditor_address:, debtor_address:,
                         creditline_given:, creditline_received:)
      body = {
        creditor_address: creditor_address,
        debtor_address: debtor_address,
        creditline_given: creditline_given,
        creditline_received: creditline_received
      }
      return post("/api/v1/networks/#{network_address}/trustlines/update", body) unless Foaf::Config.shared_writes?

      shared_write(:update_trustline) do
        @shared_client.update_trustline(
          network_address: network_address,
          **body
        )
      end
    end

    def user_trustlines(network_address:, user_address:)
      compare_read(
        :user_trustlines,
        legacy: -> { get("/api/v1/networks/#{network_address}/users/#{user_address}/trustlines") }
      ) do
        @shared_client.user_trustlines(
          network_address: network_address,
          user_address: user_address
        )
      end
    end

    # === TRANSFERS ===

    def create_pending_transfer(network_address:, from_address:, to_address:,
                                value:, extra_data: nil)
      body = {
        network_address: network_address,
        from_address: from_address,
        to_address: to_address,
        value: value,
        extra_data: extra_data
      }
      return post("/api/v1/pending_transfers", body) unless Foaf::Config.shared_writes?

      shared_write(:create_pending_transfer) do
        @shared_client.create_pending_transfer(**body)
      end
    end

    def confirm_transfer(pending_transfer_id:, signer_address: nil)
      unless Foaf::Config.shared_writes?
        return put("/api/v1/pending_transfers/#{pending_transfer_id}/confirm")
      end

      shared_write(:confirm_transfer) do
        @shared_client.confirm_transfer(
          pending_transfer_id: pending_transfer_id,
          signer_address: signer_address
        )
      end
    end

    def reject_transfer(pending_transfer_id:, signer_address: nil, reason: nil)
      unless Foaf::Config.shared_writes?
        body = reason.nil? ? {} : { reason: reason }
        return put("/api/v1/pending_transfers/#{pending_transfer_id}/reject", body)
      end

      shared_write(:reject_transfer) do
        @shared_client.reject_transfer(
          pending_transfer_id: pending_transfer_id,
          signer_address: signer_address,
          reason: reason
        )
      end
    end

    # === EVENTS ===

    def user_events(network_address:, user_address:, type: nil)
      params = {}
      params[:type] = type if type
      compare_read(
        :user_events,
        legacy: -> { get("/api/v1/networks/#{network_address}/users/#{user_address}/events", params) }
      ) do
        @shared_client.user_events(
          network_address: network_address,
          user_address: user_address,
          type: type
        )
      end
    end

    # Events scoped to a specific trustline edge (both directions). Includes
    # per-hop BalanceUpdate events that would otherwise be invisible in a
    # user-scoped feed — notably, credloop cancellations that pass through
    # this edge but whose Transfer event targets a different user.
    def trustline_events(network_address:, user_address:, counter_party_address:, type: nil)
      params = {}
      params[:type] = type if type
      compare_read(
        :trustline_events,
        legacy: lambda do
          get(
            "/api/v1/networks/#{network_address}/users/#{user_address}/trustlines/#{counter_party_address}/events",
            params
          )
        end
      ) do
        @shared_client.trustline_events(
          network_address: network_address,
          user_address: user_address,
          counter_party_address: counter_party_address,
          type: type
        )
      end
    end

    # === OPERATIONS (generic reads for indexers) ===
    # Protocol exposes raw operations + events; all analytics (credloops,
    # reports, graphs) live in this backend as consumer-side indexing.

    def operations(network_address:, limit: 20, type: nil, since_id: nil, before_id: nil, actor_address: nil)
      params = { limit: limit }
      params[:type] = type if type
      params[:since_id] = since_id if since_id
      params[:before_id] = before_id if before_id
      params[:actor_address] = actor_address if actor_address
      compare_read(
        :operations,
        legacy: -> { get("/api/v1/networks/#{network_address}/operations", params) }
      ) do
        @shared_client.operations(
          network_address: network_address,
          limit: limit,
          type: type,
          since_id: since_id,
          before_id: before_id,
          actor_address: actor_address
        )
      end
    end

    def operation(operation_id:)
      compare_read(:operation, legacy: -> { get("/api/v1/operations/#{operation_id}") }) do
        @shared_client.operation(operation_id: operation_id)
      end
    end

    private

    def shared_write(name)
      result = yield
      return result["data"] if result.is_a?(Hash) && result["ok"] == true

      status = result.is_a?(Hash) ? result["status"] : nil
      error = result.is_a?(Hash) ? result["error"] : result.inspect
      Rails.logger.warn(
        "[foaf-client write] method=#{name} failed status=#{status || "unknown"} " \
        "error=#{error.to_s[0, 500]}"
      )
      nil
    rescue StandardError => e
      Rails.logger.warn("[foaf-client write] method=#{name} raised: #{e.message}")
      nil
    end

    def sign_shared_payload(address, payload)
      user = User.where("LOWER(foaf_address) = ?", address.to_s.downcase).first
      unless user
        Rails.logger.warn("[foaf-client write] no local signer for address=#{address}")
        return nil
      end

      Foaf::Signer.sign(user, payload)
    end

    def compare_read(name, legacy:)
      legacy_result = legacy.call
      shared_result = yield
      if normalized(legacy_result) != normalized(shared_result)
        Rails.logger.warn(
          "[foaf-client shadow diff] method=#{name} legacy=#{legacy_result.inspect} " \
          "shared=#{shared_result.inspect}"
        )
      end
      Foaf::Config.shared_reads? ? shared_result : legacy_result
    rescue StandardError => e
      Rails.logger.warn("[foaf-client shadow diff] method=#{name} failed: #{e.message}")
      legacy_result
    end

    def normalized(value)
      JSON.parse(JSON.generate(value))
    rescue JSON::GeneratorError, JSON::ParserError
      value
    end

    def get(path, params = {})
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      response = Net::HTTP.get_response(uri)
      parse_response(response)
    rescue StandardError => e
      log_error("GET #{path}", e)
      nil
    end

    def post(path, body = {})
      uri = URI("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      request.body = body.to_json
      response = http.request(request)
      parse_response(response)
    rescue StandardError => e
      log_error("POST #{path}", e)
      nil
    end

    def put(path, body = {})
      uri = URI("#{@base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Put.new(uri.path, "Content-Type" => "application/json")
      request.body = body.to_json
      response = http.request(request)
      parse_response(response)
    rescue StandardError => e
      log_error("PUT #{path}", e)
      nil
    end

    def parse_response(response)
      return nil unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue JSON::ParserError
      response.body
    end

    def log_error(method, error)
      Rails.logger.warn("[FOAF Shadow] #{method} failed: #{error.message}")
    end
  end
end
