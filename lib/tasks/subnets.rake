namespace :subnets do
  desc <<~DESC
    Create the primary subnet, enroll the invite chain, backfill invitations.

    Optional env vars (omit to accept SiteConfig defaults):
      SUBNET_NAME            — display name. Default: "<Seed>'s Network"
      SUBNET_MULTI_ROLE      — true|false
      SUBNET_VISIBLE_ROLES   — comma-separated role names (e.g. "broker,producer")
      SUBNET_CHAIN_LIMIT     — integer

    Example (launch-locked prod subnet):
      SUBNET_NAME="Crawford Bay" SUBNET_MULTI_ROLE=false \
        SUBNET_VISIBLE_ROLES=broker \
        rake subnets:backfill
  DESC
  task backfill: :environment do
    SubnetBackfill.run!(
      logger: ->(msg) { puts msg },
      subnet_name: ENV['SUBNET_NAME'],
      config: config_from_env
    )
  end

  def config_from_env
    cfg = {}
    cfg[:multi_role] = parse_bool(ENV['SUBNET_MULTI_ROLE']) if ENV['SUBNET_MULTI_ROLE']
    cfg[:visible_roles] = ENV['SUBNET_VISIBLE_ROLES'].split(',').map(&:strip) if ENV['SUBNET_VISIBLE_ROLES']
    cfg[:chain_limit] = ENV['SUBNET_CHAIN_LIMIT'].to_i if ENV['SUBNET_CHAIN_LIMIT']
    cfg.empty? ? nil : cfg
  end

  def parse_bool(v)
    %w[true 1 yes].include?(v.to_s.strip.downcase)
  end
end
