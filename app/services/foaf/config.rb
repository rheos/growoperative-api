# frozen_string_literal: true

# Single point of control for FOAF shadow mode.
# Set FOAF_SHADOW_MODE=true in docker-compose environment to enable.
# Only enable in development — production uses the existing trustline code.

module Foaf
  module Config
    module_function

    def shadow_mode?
      ENV["FOAF_SHADOW_MODE"] == "true"
    end

    def api_url
      ENV.fetch("FOAF_API_URL", "http://foaf:3002")
    end

    # Shared reads parallel-run against the legacy client and log any mismatch.
    def shared_reads?
      ENV["FOAF_SHARED_READS"] == "true"
    end

    # Shared writes are single-run: a failed request must never fall through to
    # the legacy transport because the upstream mutation may already have
    # committed even when the response was lost. Set false for instant rollback.
    def shared_writes?
      ENV["FOAF_SHARED_WRITES"] == "true"
    end
  end
end
