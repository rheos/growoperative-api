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
  end
end
