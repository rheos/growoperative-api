class Markup
  TYPES = %w[flat percent].freeze

  attr_reader :type, :value

  def self.flat(value)
    new(type: 'flat', value: value)
  end

  def self.percent(value)
    new(type: 'percent', value: value)
  end

  def self.from_record(record)
    new(type: record.try(:price_type) || 'flat', value: record.price)
  end

  def self.type_from_setting(value)
    value.to_i == 1 ? 'percent' : 'flat'
  end

  def self.setting_value_for(type)
    type.to_s == 'percent' ? 1 : 0
  end

  def initialize(type:, value:)
    @type = TYPES.include?(type.to_s) ? type.to_s : 'flat'
    @value = value.to_f
  end

  def apply_to(base)
    amount = base.to_f
    raw = percent? ? amount * (1 + value / 100.0) : amount + value
    (raw * 20).round / 20.0
  end

  def percent?
    type == 'percent'
  end

  def zero?
    value.zero?
  end

  def to_h
    { type: type, value: value }
  end
end
