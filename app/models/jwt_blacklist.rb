class JWTBlacklist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist

  self.table_name = 'jwt_blacklist'

  # Clean up tokens older than 1 week after creating a new one
  after_create :cleanup_old_tokens

  private

  def cleanup_old_tokens
    # Convert Unix timestamp to datetime for comparison
    cutoff_time = Time.at(1.week.ago.to_i)
    self.class.where('exp < ?', cutoff_time).delete_all
  end
end
