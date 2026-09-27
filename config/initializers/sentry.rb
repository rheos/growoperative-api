# Error tracking for api.growoperative.app.
#
# Inert unless SENTRY_DSN is set, so development, test and CI configure nothing
# and send nothing. The DSN is set only on the production Coolify app.
#
# Context: until 2026-09-27 the entire Rails fleet had no error tracking of any
# kind. An exception went to container stdout under a 10MB/3-file rotation and
# nowhere else. The health probe added the same day catches a dead database,
# not a 500 on one endpoint — those were, and otherwise remain, invisible.
return if ENV["SENTRY_DSN"].to_s.strip.empty?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)

  # Belt and braces with the `return` above: even if a DSN leaks into another
  # tier's env, only production reports.
  config.enabled_environments = %w[production]

  # NEVER enable this here. This app holds user identities, orders and mutual-credit balances; send_default_pii would attach request bodies, headers and user context to every event.
  config.send_default_pii = false

  # Scrub with the SAME list Rails uses for logs rather than a second list that
  # can drift. sentry-rails applies this already; doing it explicitly means the
  # guarantee survives a future gem default change.
  parameter_filter = ActiveSupport::ParameterFilter.new(
    Rails.application.config.filter_parameters
  )
  config.before_send = lambda do |event, _hint|
    begin
      data = event.request&.data
      event.request.data = parameter_filter.filter(data) if data.is_a?(Hash)
    rescue StandardError => e
      # A scrubbing failure must never swallow the error being reported, and
      # must never let an unscrubbed body through either.
      Rails.logger.error("[sentry] before_send scrub failed: #{e.class}")
      event.request.data = { "scrubbed" => "before_send failed" } if event.request
    end
    event
  end

  # Only the sentry logger. The default set includes active_support_logger,
  # whose SQL breadcrumbs carry query values — that would attach row data to
  # every unrelated exception.
  config.breadcrumbs_logger = [:sentry_logger]

  # Errors only. Performance tracing would burn the event quota on a service
  # whose value here is "tell me when something raised".
  config.traces_sample_rate = 0.0

  # Lets Sentry group regressions by deploy.
  config.release = ENV["SOURCE_COMMIT"] || ENV["COOLIFY_RESOURCE_UUID"]
end
