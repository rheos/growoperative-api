class UserSerializer
  include FastJsonapi::ObjectSerializer
  attributes :id, :user_name, :name, :nickname, :tokens, :created_at, :invite_limit

  attributes :user_types do |object|
    object.user_groups
  end

  attribute :avatar_url do |object|
    object.avatar_url
  end
end
