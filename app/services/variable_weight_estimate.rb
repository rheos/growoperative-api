# Pure pricing math for variable-weight "buy a share" listings (meat).
#
# Billing is ALWAYS on carcass (hanging) weight. The cut / take-home weight a
# buyer actually carries away is a yield fraction of that (~0.6 for beef), so
# the effective cost per pound of *packaged* meat is higher than the carcass
# rate. Producers who quote a milder loss just set a higher yield factor.
#
# Dependency-free on purpose: unit-testable without the DB, and reusable from
# Item, serializers, and (Increment 2) the settlement path.
module VariableWeightEstimate
  module_function

  # Effective per-lb rate the buyer is billed at. On-the-rail knocks the delta
  # off the base rate (the buyer arranges their own butcher). Never negative.
  def billed_rate(base_rate, on_the_rail_delta = 0, on_the_rail: false)
    return nil if base_rate.nil?
    rate = to_d(base_rate)
    rate -= to_d(on_the_rail_delta) if on_the_rail
    rate.negative? ? BigDecimal(0) : rate
  end

  # Billed total for a known carcass weight.
  def billed_total(rate, carcass_weight)
    return nil if rate.nil? || carcass_weight.nil?
    to_d(rate) * to_d(carcass_weight)
  end

  # [low, high] billed estimate across a carcass-weight range.
  def billed_range(rate, weight_min, weight_max)
    return nil if rate.nil? || weight_min.nil? || weight_max.nil?
    [billed_total(rate, weight_min), billed_total(rate, weight_max)]
  end

  # Take-home (packaged cut) weight = carcass weight * yield factor.
  def take_home_weight(carcass_weight, yield_factor)
    return nil if carcass_weight.nil? || yield_factor.nil?
    to_d(carcass_weight) * to_d(yield_factor)
  end

  # [low, high] take-home weight across a carcass-weight range.
  def take_home_range(weight_min, weight_max, yield_factor)
    return nil if weight_min.nil? || weight_max.nil? || yield_factor.nil?
    [take_home_weight(weight_min, yield_factor), take_home_weight(weight_max, yield_factor)]
  end

  # Effective $/lb of PACKAGED meat: what the buyer pays divided by what they
  # take home = billed_rate / yield_factor. This is the honest "you pay $X per
  # pound of meat you actually receive" number, and it's what makes bulk a good
  # deal (cheap per lb once you account for the prime cuts you get). Nil if the
  # yield factor is zero.
  def packaged_rate(billed_rate, yield_factor)
    return nil if billed_rate.nil? || yield_factor.nil?
    yf = to_d(yield_factor)
    return nil if yf.zero?
    to_d(billed_rate) / yf
  end

  # Midpoint of a carcass-weight range. What a claimed share is booked at before
  # anything has been on a scale — an honest centre of the advertised range,
  # never a number anyone is billed on.
  def midpoint(weight_min, weight_max)
    return nil if weight_min.nil? || weight_max.nil?
    (to_d(weight_min) + to_d(weight_max)) / 2
  end

  # Expected total carcass weight for `shares` of a listing whose single share
  # is advertised at weight_min..weight_max.
  def estimated_weight(weight_min, weight_max, shares)
    mid = midpoint(weight_min, weight_max)
    return nil if mid.nil? || shares.nil?
    mid * to_d(shares)
  end

  def to_d(value)
    value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
  end
end
