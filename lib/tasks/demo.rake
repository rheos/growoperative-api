namespace :demo do
  CORE_DEMO_USERNAMES = %w[bob dianna peter paul sara mary bruce arthur clark oliver barry mark john].freeze

  desc "Mark existing seed users with the 'demo' user group"
  task mark_users: :environment do
    count = 0
    CORE_DEMO_USERNAMES.each do |name|
      user = User.find_by(user_name: name)
      if user
        user.user_groups.find_or_create_by!(group_label: 'demo')
        count += 1
        puts "  Marked #{name} as demo"
      else
        puts "  SKIP: #{name} not found"
      end
    end
    puts "Done — #{count} users marked as demo"
  end

  desc "Capture demo data snapshot to db/demo_snapshot.json"
  task snapshot: :environment do
    require_relative '../../app/services/demo_snapshot_service'
    DemoSnapshotService.new.capture
    puts "Snapshot saved to db/demo_snapshot.json"
  end

  desc "Reset demo data from snapshot (deletes spawned users, restores core demo data)"
  task reset: :environment do
    require_relative '../../app/services/demo_reset_service'
    DemoResetService.new.call
    puts "Demo data reset complete"
  end
end
