class Invitation < ApplicationRecord
  # It handle status value as enum
  enum status: [ :pending, :accepted ]
  enum user_type: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin]
  belongs_to :user
  belongs_to :subnet, optional: true

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

  # Random-code fallback for cases where the controller doesn't pre-fill
  # `invitation_code` from auth.foaf.io. Skipped when the code is already
  # set (the canonical pronounceable-from-FOAF path).
  def generate_invitation_code
    return if invitation_code.present?
    size = 8
    charset = ([*('A'..'Z'),*('0'..'9')]-["O"]).sample(size).join
     begin
      random_string = charset
      self.invitation_code = random_string
    end while self.class.exists?(:invitation_code => random_string)
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
