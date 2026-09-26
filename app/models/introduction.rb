class Introduction < ApplicationRecord
  belongs_to :introducer,   class_name: 'User'
  belongs_to :introducee_a, class_name: 'User'
  belongs_to :introducee_b, class_name: 'User'
  belongs_to :declined_by,  class_name: 'User', optional: true, foreign_key: :declined_by_id

  enum :status, { pending: 0, completed: 1, declined: 2 }
  # Transitions are one-way: pending → completed | declined (enforced in controller)

  # Returns true if user_id has already accepted their side.
  def accepted_by?(user_id)
    user_id == introducee_a_id ? accepted_a_at.present? : accepted_b_at.present?
  end

  # Sets the acceptance timestamp for this user. Idempotent (no-op if already set).
  def accept_for!(user_id)
    if user_id == introducee_a_id
      update!(accepted_a_at: Time.current) unless accepted_a_at?
    else
      update!(accepted_b_at: Time.current) unless accepted_b_at?
    end
  end

  # True if the user is the introducer or either introducee.
  def party?(user_id)
    user_id == introducer_id || user_id == introducee_a_id || user_id == introducee_b_id
  end

  # True when both introducees have accepted.
  def both_accepted?
    accepted_a_at? && accepted_b_at?
  end

  # True when all three parties (introducer, introducee_a, introducee_b) have the same demo? status.
  def demo_consistent?
    [introducer, introducee_a, introducee_b].map(&:demo?).uniq.size == 1
  end
end
