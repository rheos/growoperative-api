class SubnetConfig < ApplicationRecord
  belongs_to :subnet
  belongs_to :changed_by_user, class_name: 'User', optional: true

  validates :version, presence: true, uniqueness: { scope: :subnet_id }

  # Append-only: rows are inserted per change, never updated. This preserves the
  # full history of flag changes and keeps the shape compatible with a future
  # on-chain migration where state transitions are naturally versioned.
  before_update { raise ActiveRecord::ReadOnlyRecord, 'SubnetConfig is append-only' }
end
