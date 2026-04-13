module Notifications
  # Convenience entry point so call sites stay one-line:
  #
  #   Notifications.publish!(event: :request_created, actor: current_user, ...)
  #
  def self.publish!(event:, actor:, recipients:, resource: nil, metadata: {})
    Publisher.call(
      event:      event,
      actor:      actor,
      recipients: recipients,
      resource:   resource,
      metadata:   metadata
    )
  end
end
