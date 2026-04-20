namespace :subnets do
  desc "Create growoperative + demo subnets, seed initial configs, and backfill memberships + invitations"
  task backfill: :environment do
    SubnetBackfill.run!(logger: ->(msg) { puts msg })
  end
end
