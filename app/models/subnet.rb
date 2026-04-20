class Subnet < ApplicationRecord
  belongs_to :seed_user, class_name: 'User'

  has_many :subnet_memberships, dependent: :destroy
  has_many :users, through: :subnet_memberships
  has_many :subnet_configs, dependent: :destroy
  has_many :invitations

  validates :name, presence: true

  def current_config
    subnet_configs.order(version: :desc).first
  end

  def next_config_version
    (subnet_configs.maximum(:version) || 0) + 1
  end
end
