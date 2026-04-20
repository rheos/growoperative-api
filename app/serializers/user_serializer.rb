class UserSerializer
  include FastJsonapi::ObjectSerializer
  attributes :id, :user_name, :name, :nickname, :tokens, :created_at, :invite_limit

  attributes :user_types do |object|
    object.user_groups
  end

  attribute :avatar_url do |object|
    object.avatar_url
  end

  attribute :subnet_memberships do |object|
    object.subnet_memberships.includes(:subnet).map do |m|
      {
        id: m.id,
        subnet_id: m.subnet_id,
        subnet_name: m.subnet.name,
        is_primary: m.is_primary
      }
    end
  end
end
