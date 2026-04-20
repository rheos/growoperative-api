class SubnetBackfill
  # Seeds the primary subnet for a deployment, enrolls the seed user and
  # everyone rooted in their invite chain, and backfills any pending
  # invitations with subnet_id=nil to point at the new subnet.
  #
  # Idempotent: find_or_create_by on the subnet, enrolment guarded by
  # `exists?` check per user, config row only seeded if absent.
  #
  # Parameters:
  #   subnet_name — display name for the subnet. Defaults to "<Seed>'s Network".
  #   config      — flag hash stored on the initial SubnetConfig row. When nil,
  #                 the subnet uses SiteConfig::DEFAULTS via the resolver.
  def self.run!(logger: ->(_) {}, subnet_name: nil, config: nil)
    new(logger: logger, subnet_name: subnet_name, config: config).run!
  end

  def initialize(logger:, subnet_name: nil, config: nil)
    @log = logger
    @override_name = subnet_name
    @override_config = config
  end

  def run!
    ActiveRecord::Base.transaction do
      seed = User.order(:id).first
      raise "No users exist — cannot backfill subnets" if seed.nil?

      subnet = Subnet.find_or_create_by!(seed_user_id: seed.id) do |s|
        s.name = @override_name || "#{seed.user_name.capitalize}'s Network"
      end

      seed_config!(subnet)
      backfill_memberships!(subnet)
      backfill_invitations!(subnet)

      @log.call "Backfill complete:"
      @log.call "  subnet:                #{subnet.id} (#{subnet.name}, seed=#{seed.user_name})"
      @log.call "  config:                #{subnet.current_config.config.inspect}"
      @log.call "  memberships:           #{subnet.subnet_memberships.count}"
      @log.call "  invitations w/ subnet: #{Invitation.where.not(subnet_id: nil).count}/#{Invitation.count}"
    end
  end

  private

  def seed_config!(subnet)
    return if subnet.subnet_configs.exists?
    SubnetConfig.create!(subnet: subnet, version: 1, config: config_to_seed)
  end

  def config_to_seed
    return @override_config if @override_config
    # Minimal default: pull chain_limit from GlobalSetting so existing behaviour
    # is preserved. Other flags fall through to SiteConfig::DEFAULTS via the
    # resolver — no opinion about multi_role or demo_mode from the backfill.
    { chain_limit: chain_limit_default }
  end

  def backfill_memberships!(subnet)
    rooted = users_rooted_at(subnet.seed_user_id)
    rooted.each do |user|
      next if user.subnet_memberships.exists?
      user.subnet_memberships.create!(subnet: subnet, is_primary: true)
    end
  end

  def users_rooted_at(root_id)
    collected = [User.find(root_id)]
    frontier = [root_id]
    until frontier.empty?
      children = User.where(parent_id: frontier).to_a
      collected.concat(children)
      frontier = children.map(&:id)
    end
    collected
  end

  def backfill_invitations!(subnet)
    Invitation.where(subnet_id: nil).find_each do |inv|
      primary = inv.user&.primary_subnet
      inv.update_column(:subnet_id, primary.id) if primary
    end
  end

  def chain_limit_default
    GlobalSetting.find_by(setting: 'ChainLimit')&.value&.to_i || SiteConfig::DEFAULTS[:chain_limit]
  end
end
