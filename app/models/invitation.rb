class Invitation < ApplicationRecord
  EASY_CODE_MIN_LENGTH = 3
  EASY_CODE_MAX_LENGTH = 16
  EASY_CODE_PATTERN = /\A[A-Z0-9]{#{EASY_CODE_MIN_LENGTH},#{EASY_CODE_MAX_LENGTH}}\z/.freeze
  EASY_CODE_CHARS = (('A'..'Z').to_a + ('2'..'9').to_a - %w[I O]).freeze

  # It handle status value as enum
  enum status: [ :pending, :accepted ]
  enum user_type: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin]
  belongs_to :user
  belongs_to :subnet, optional: true
  has_many :invitation_redemptions, dependent: :destroy
  has_many :redeemers, through: :invitation_redemptions, source: :user

  # Callbacks
  before_validation :canonicalize_invitation_code
  validate :invitation_code_has_easy_shape
  validate :invitation_code_is_available_while_active
  before_create :generate_invitation_code
  after_create :set_user_type

  scope :active_code_rows, -> { pending.where(disabled_at: nil) }

  # Strip separators + uppercase so codes from any source (legacy random,
  # auth.foaf.io pronounceable like "mavo-leni") and any user-typed form
  # ("MAVO LENI", "mavo-leni", "MaVoLeNi") canonicalize identically.
  # Old stored codes were already uppercase alphanumeric; this is a no-op
  # for them.
  def self.canonicalize_code(raw)
    return nil if raw.blank?
    raw.to_s.gsub(/[\s\-_\/]/, '').upcase
  end

  def self.easy_code?(raw)
    canonical = canonicalize_code(raw)
    canonical.present? && canonical.match?(EASY_CODE_PATTERN)
  end

  def self.active_code_taken?(raw, except_id: nil)
    canonical = canonicalize_code(raw)
    return false if canonical.blank?

    rows = active_code_rows.where(invitation_code: canonical)
    rows = rows.where.not(id: except_id) if except_id.present?
    rows.exists?
  end

  # Lookup wrapper that canonicalizes the input. Use this everywhere in
  # place of `find_by(invitation_code: raw)` so user-typed casing /
  # separators don't matter at the DB lookup boundary. Active rows win
  # when a retired code has later been reused.
  def self.find_by_code(raw)
    canonical = canonicalize_code(raw)
    return nil if canonical.blank?
    active_code_rows.where(invitation_code: canonical).order(created_at: :desc).first ||
      where(invitation_code: canonical).order(created_at: :desc).first
  end

  def canonicalize_invitation_code
    return if invitation_code.blank?
    self.invitation_code = self.class.canonicalize_code(invitation_code)
  end

  # A multi-use code can be redeemed by many people and never goes terminal
  # (status stays pending). `active?` is the on/off switch — null disabled_at
  # means the creator hasn't turned it off.
  def active?
    pending? && disabled_at.nil?
  end

  # Random-code fallback for cases where the controller doesn't pre-fill
  # `invitation_code` from auth.foaf.io. Skipped when the code is already
  # set (the canonical pronounceable-from-FOAF path).
  def generate_invitation_code
    return if invitation_code.present?
    20.times do
      random_string = Array.new(6) { EASY_CODE_CHARS.sample }.join
      unless self.class.active_code_taken?(random_string)
        self.invitation_code = random_string
        return
      end
    end
    self.invitation_code = Array.new(8) { EASY_CODE_CHARS.sample }.join
  end

  def invitation_code_has_easy_shape
    return if invitation_code.blank? || self.class.easy_code?(invitation_code)
    errors.add(:invitation_code, "must be #{EASY_CODE_MIN_LENGTH}-#{EASY_CODE_MAX_LENGTH} letters or numbers")
  end

  def invitation_code_is_available_while_active
    return unless invitation_code.present? && active?
    return unless self.class.active_code_taken?(invitation_code, except_id: id)
    errors.add(:invitation_code, "is already active")
  end


  def set_user_type
    if self.user_type == ''
      user_type = self.user.user_groups.pluck(:group_label)
      case user_type
      when user_type.include?("admin")
        self.update user_type: "producer"
      when user_type.include?("producer")
        self.update user_type: "producer"
      when user_type.include?("wholesaler")
        self.update user_type: "producer"
      when user_type.include?("broker")
        self.update user_type: "broker"
      when user_type.include?("retailer")
        self.update user_type: "consumer"
      when user_type.include?("consumer")
        self.update user_type: "consumer"
      end
    end
  end
end
