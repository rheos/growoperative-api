class SiteConfig
  DEFAULTS = {
    multi_role: true,
    demo_mode: false,
    enforce_valid_email: false,
    visible_roles: %w[producer broker wholesaler retailer consumer],
    chain_limit: 3,
    default_markup: 10,
    default_markup_type: 'percent',
    show_mutual_contacts: true,
    # ISO 4217. Display only for now — CAD and USD both render as "$".
    # Ledger isolation per currency is a later change.
    currency: 'CAD'
  }.freeze

  # Currencies a new subnet can pick. Keep in sync with
  # growoperative-app `SITE_CURRENCIES`.
  CURRENCIES = %w[
    CAD USD EUR GBP CHF SEK NOK DKK PLN CZK HUF
    JPY KRW AUD NZD MXN BRL INR IDR VND ZAR
  ].freeze

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

  # Shared whitelist for seed-invitation mint and PATCH /v1/subnets/:id/config.
  # Unknown keys are dropped. Unknown currency codes are dropped (caller keeps
  # the previous / default value).
  def self.permit_flags(source)
    p = indifferent_params(source)
    allowed = {}
    if p.key?(:multi_role)
      allowed[:multi_role] = to_bool(p[:multi_role])
    end
    if p.key?(:show_mutual_contacts)
      allowed[:show_mutual_contacts] = to_bool(p[:show_mutual_contacts])
    end
    if p.key?(:enforce_valid_email)
      allowed[:enforce_valid_email] = to_bool(p[:enforce_valid_email])
    end
    if p.key?(:visible_roles)
      roles = Array(p[:visible_roles]).map(&:to_s).reject(&:empty?)
      allowed[:visible_roles] = roles
    end
    if p.key?(:chain_limit) && p[:chain_limit].present?
      allowed[:chain_limit] = p[:chain_limit].to_i
    end
    if p.key?(:default_markup) && p[:default_markup].present?
      allowed[:default_markup] = p[:default_markup].to_f
    end
    if p.key?(:default_markup_type) && p[:default_markup_type].present?
      type = p[:default_markup_type].to_s
      allowed[:default_markup_type] = Markup::TYPES.include?(type) ? type : 'flat'
    end
    if p.key?(:currency) && p[:currency].present?
      code = normalize_currency(p[:currency])
      allowed[:currency] = code if code
    end
    allowed
  end

  def self.normalize_currency(value)
    code = value.to_s.strip.upcase
    CURRENCIES.include?(code) ? code : nil
  end

  def self.symbolize_keys(hash)
    hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
  end
  private_class_method :symbolize_keys

  def self.to_bool(v)
    return v if v == true || v == false
    %w[true 1 yes].include?(v.to_s.downcase)
  end
  private_class_method :to_bool

  def self.indifferent_params(source)
    hash = if source.respond_to?(:to_unsafe_h)
      source.to_unsafe_h
    elsif source.respond_to?(:to_h)
      source.to_h
    else
      source
    end
    hash.to_h.with_indifferent_access
  end
  private_class_method :indifferent_params
end
