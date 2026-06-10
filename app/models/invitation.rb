class Invitation < ApplicationRecord
  # Reconciliation states for `foaf_invitation_state`. This column tracks how a
  # local invitation row relates to its authoritative FOAF (auth.foaf.io)
  # counterpart during the issuance-authority migration. Writers (the dual-write
  # controller in Step 07, redemption/reconciliation in Step 08) set these via
  # the constants rather than magic strings. Internal infrastructure — no
  # validation.
  FOAF_STATE_UNSYNCED   = 'unsynced'.freeze   # local row created, not yet pushed to FOAF
  FOAF_STATE_SYNCED     = 'synced'.freeze      # FOAF accepted the write; auth_invitation_id set
  FOAF_STATE_FAILED     = 'failed'.freeze      # FOAF write attempted and failed; needs retry/reconcile
  FOAF_STATE_RECONCILED = 'reconciled'.freeze  # divergence resolved by a later reconciliation pass

  # It handle status value as enum
  enum status: [ :pending, :accepted ]
  enum user_type: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin]
  belongs_to :user
  belongs_to :subnet, optional: true
  has_many :invitation_redemptions, dependent: :destroy
  has_many :redeemers, through: :invitation_redemptions, source: :user

  # Callbacks
  before_validation :canonicalize_invitation_code
  before_create :generate_invitation_code
  after_create :set_user_type

  # Strip separators + uppercase so codes from any source (legacy random,
  # auth.foaf.io pronounceable like "mavo-leni") and any user-typed form
  # ("MAVO LENI", "mavo-leni", "MaVoLeNi") canonicalize identically.
  # Old stored codes were already uppercase alphanumeric; this is a no-op
  # for them.
  def self.canonicalize_code(raw)
    return nil if raw.blank?
    raw.to_s.gsub(/[\s\-_\/]/, '').upcase
  end

  # Lookup wrapper that canonicalizes the input. Use this everywhere in
  # place of `find_by(invitation_code: raw)` so user-typed casing /
  # separators don't matter at the DB lookup boundary.
  def self.find_by_code(raw)
    canonical = canonicalize_code(raw)
    return nil if canonical.blank?
    find_by(invitation_code: canonical)
  end

  def canonicalize_invitation_code
    return if invitation_code.blank?
    self.invitation_code = self.class.canonicalize_code(invitation_code)
  end

  # A multi-use code can be redeemed by many people and never goes terminal
  # (status stays pending). `active?` is the on/off switch — null disabled_at
  # means the creator hasn't turned it off.
  def active?
    disabled_at.nil?
  end

  # Random-code fallback for cases where the controller doesn't pre-fill
  # `invitation_code` from auth.foaf.io. Skipped when the code is already
  # set (the canonical pronounceable-from-FOAF path).
  def generate_invitation_code
    return if invitation_code.present?
    size = 8
    begin
      charset = ([*('A'..'Z'), *('0'..'9')] - ['O'])
      random_string = charset.sample(size).join
    end while Invitation.exists?(invitation_code: random_string)
    self.invitation_code = random_string
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
