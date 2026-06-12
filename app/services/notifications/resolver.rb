module Notifications
  class Resolver
    def self.call(record)
      return if record.nil?

      subject_type = record.class.name
      Notification.unresolved
                  .where(subject_type: subject_type, subject_id: record.id)
                  .find_each do |notification|
        reason = resolved_when_for(notification, record)
        notification.resolve!(reason) if reason
      end
    rescue => e
      Rails.logger.error("[Notifications::Resolver] error resolving #{record.class}##{record.id}: #{e.message}")
    end

    private_class_method def self.resolved_when_for(notification, record)
      # notification.notification_type is a STRING; EVENTS hash uses SYMBOL keys — to_sym is required.
      registry_entry = Notifications::EventRegistry.fetch(notification.notification_type.to_sym)
      return nil unless registry_entry&.key?(:resolved_when)
      registry_entry[:resolved_when].call(subject: record)
    rescue ArgumentError
      # EventRegistry.fetch raises ArgumentError for unknown events — treat as no resolver.
      nil
    rescue => e
      Rails.logger.error("[Notifications::Resolver] resolved_when error for notification #{notification.id}: #{e.message}")
      nil
    end
  end
end
