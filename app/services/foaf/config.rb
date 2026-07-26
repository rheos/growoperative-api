# frozen_string_literal: true

# Single point of control for publishing GrowOperative ledger writes to FOAF.
#
# FOAF_WRITE_ENABLED is the current name. FOAF_SHADOW_MODE remains an
# intentionally temporary compatibility bridge during the config/image rollout:
# either variable enables publishing, so a mixed deployment cannot silently
# switch the publisher off.

module Foaf
  module Config
    module_function

    def foaf_write_enabled?
      ENV["FOAF_WRITE_ENABLED"] == "true" ||
        ENV["FOAF_SHADOW_MODE"] == "true"
    end

    def api_url
      ENV.fetch("FOAF_API_URL", "http://foaf:3002")
    end

    # Shared reads parallel-run against the legacy client and log any mismatch.
    def shared_reads?
      ENV["FOAF_SHARED_READS"] == "true"
    end

    # Shared writes are single-run: a failed request never falls through to
    # another transport because the upstream mutation may already have committed
    # even when the response was lost. Set false to stop mutations and retain
    # operations in the durable Rails buffers for later idempotent replay.
    def shared_writes?
      ENV["FOAF_SHARED_WRITES"] == "true"
    end
  end
end
