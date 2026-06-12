namespace :notifications do
  desc "Re-run the Resolver over all unresolved notifications that have a subject. " \
       "Idempotent self-heal for resolver errors or hook-bypassing writes."
  task reconcile: :environment do
    resolved_count = 0
    live_count     = 0

    Notification.unresolved.where.not(subject_type: nil).find_each do |n|
      subject = n.subject_type.constantize.find_by(id: n.subject_id)

      if subject.nil?
        # Subject has been deleted. The Resolver's nil guard returns immediately for nil
        # (and an OpenStruct workaround breaks: record.class.name resolves to "OpenStruct",
        # so the Resolver finds 0 rows matching subject_type=ItemRequest). Call resolve!
        # directly on the notification instead.
        n.resolve!(:orphaned)
        resolved_count += 1
      else
        # Subject exists — route through the Resolver so resolved_when logic applies.
        Notifications.resolve!(subject)
        n.reload
        resolved_count += 1 if n.resolved_at?
        live_count     += 1 unless n.resolved_at?
      end
    end

    Rails.logger.info("[notifications:reconcile] resolved: #{resolved_count}, still-live: #{live_count}")
    puts "Reconcile complete — resolved: #{resolved_count}, still-live: #{live_count}"
  end
end
