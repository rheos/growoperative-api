# frozen_string_literal: true

# Durable Rails-side publication record for FOAF writes that do not already
# have a TrustlineTransaction row. Balance writes keep using their transaction
# row; trustline-limit updates use this outbox.
class FoafOutboxEntry < ApplicationRecord
  TRUSTLINE_UPDATE = "trustline_update"

  belongs_to :trustline

  validates :operation_type, inclusion: { in: [TRUSTLINE_UPDATE] }
  validates :payload, presence: true
  validates :foaf_write_state, presence: true

  scope :active, -> { where(foaf_posted_at: nil, superseded_at: nil) }
  scope :trustline_updates, -> { where(operation_type: TRUSTLINE_UPDATE) }
  scope :oldest_first, -> { order(:created_at, :id) }

  def self.enqueue_trustline_update!(trustline)
    now = Time.current

    active
      .trustline_updates
      .where(trustline_id: trustline.id)
      .update_all(
        superseded_at: now,
        foaf_write_state: "superseded",
        updated_at: now
      )

    create!(
      trustline: trustline,
      operation_type: TRUSTLINE_UPDATE,
      payload: {
        "credit_limit_a_to_b" => trustline.credit_limit_a_to_b.to_s("F"),
        "credit_limit_b_to_a" => trustline.credit_limit_b_to_a.to_s("F")
      }
    )
  end

  def self.latest_trustline_update_for(trustline)
    active
      .trustline_updates
      .where(trustline_id: trustline.id)
      .order(id: :desc)
      .first
  end

  def credit_limit_a_to_b
    BigDecimal(payload.fetch("credit_limit_a_to_b").to_s)
  end

  def credit_limit_b_to_a
    BigDecimal(payload.fetch("credit_limit_b_to_a").to_s)
  end
end
