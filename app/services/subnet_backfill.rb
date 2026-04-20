class SubnetBackfill
  def self.run!(logger: ->(_) {})
    new(logger: logger).run!
  end

  def initialize(logger:)
    @log = logger
  end

  def run!
    ActiveRecord::Base.transaction do
      seed = User.order(:id).first
      raise "No users exist — cannot backfill subnets" if seed.nil?

      subnet = Subnet.find_or_create_by!(seed_user_id: seed.id) do |s|
        s.name = "#{seed.user_name.capitalize}'s Network"
      end

      seed_config!(subnet, {
        multi_role: true,
        demo_mode: true,
        enforce_valid_email: false,
        chain_limit: chain_limit_default
      })

      backfill_memberships!(subnet)
      backfill_invitations!(subnet)

      @log.call "Backfill complete:"
      @log.call "  subnet:                #{subnet.id} (#{subnet.name}, seed=#{seed.user_name})"
      @log.call "  memberships:           #{subnet.subnet_memberships.count}"
      @log.call "  invitations w/ subnet: #{Invitation.where.not(subnet_id: nil).count}/#{Invitation.count}"
    end
  end

  private

  def seed_config!(subnet, config)
    return if subnet.subnet_configs.exists?
    SubnetConfig.create!(subnet: subnet, version: 1, config: config)
  end

  # Members are: the seed user + everyone rooted in their invite chain.
  # Users outside the chain (e.g. admins seeded separately) intentionally stay
  # out so they don't pollute the network map.
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
