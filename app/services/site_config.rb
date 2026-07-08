class SiteConfig
  DEFAULTS = {
    multi_role: true,
    demo_mode: false,
    enforce_valid_email: false,
    visible_roles: %w[producer broker wholesaler retailer consumer],
    chain_limit: 3,
    default_markup: 10,
    default_markup_type: 'percent',
    show_mutual_contacts: true
  }.freeze

  # Returns the merged flag hash for a subnet. Resolution order (first match wins):
  #   1. Current (latest version) subnet_config for the subnet
  #   2. SiteConfig::DEFAULTS
  # Keys are always returned as symbols regardless of how they were stored.
  def self.for(subnet)
    return defaults if subnet.nil?

    current = subnet.current_config
    return defaults if current.nil?

    defaults.merge(symbolize_keys(current.config))
  end

  def self.defaults
    DEFAULTS.dup
  end

  def self.symbolize_keys(hash)
    hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
  end
  private_class_method :symbolize_keys
end
