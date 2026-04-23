# frozen_string_literal: true

# HTTP client for the FOAF protocol API.
# All FOAF communication goes through this class.

require "net/http"
require "json"
require "uri"

module Foaf
  class Client
    def initialize(base_url: Foaf::Config.api_url)
      @base_url = base_url
    end

    # === KEYPAIR ===

    def generate_keypair
      post("/api/v1/keypair")
    end

    # === NETWORKS ===

    def networks
      get("/api/v1/networks")
    end

    # === TRUSTLINES ===

    def update_trustline(network_address:, creditor_address:, debtor_address:,
                         creditline_given:, creditline_received:)
      post("/api/v1/networks/#{network_address}/trustlines/update", {
        creditor_address: creditor_address,
        debtor_address: debtor_address,
        creditline_given: creditline_given,
        creditline_received: creditline_received
      })
    end

    def user_trustlines(network_address:, user_address:)
      get("/api/v1/networks/#{network_address}/users/#{user_address}/trustlines")
    end

    # === TRANSFERS ===

    def create_pending_transfer(network_address:, from_address:, to_address:,
                                value:, extra_data: nil)
      post("/api/v1/pending_transfers", {
        network_address: network_address,
        from_address: from_address,
        to_address: to_address,
        value: value,
        extra_data: extra_data
      })
    end

    def confirm_transfer(pending_transfer_id:)
      put("/api/v1/pending_transfers/#{pending_transfer_id}/confirm")
    end

    # === EVENTS ===

    def user_events(network_address:, user_address:, type: nil)
      params = {}
      params[:type] = type if type
      get("/api/v1/networks/#{network_address}/users/#{user_address}/events", params)
    end

    # Events scoped to a specific trustline edge (both directions). Includes
    # per-hop BalanceUpdate events that would otherwise be invisible in a
    # user-scoped feed — notably, credloop cancellations that pass through
    # this edge but whose Transfer event targets a different user.
    def trustline_events(network_address:, user_address:, counter_party_address:, type: nil)
      params = {}
      params[:type] = type if type
      get(
        "/api/v1/networks/#{network_address}/users/#{user_address}/trustlines/#{counter_party_address}/events",
        params,
      )
    end

    # === CREDIT LOOPS (forensic) ===

    def credloops(network_address:, limit: 20, offset: 0)
      get("/api/v1/networks/#{network_address}/credloops", limit: limit, offset: offset)
    end

    def credloop(operation_id:)
      get("/api/v1/credloops/#{operation_id}")
    end

    private

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
