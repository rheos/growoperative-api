class UserSerializer
  include FastJsonapi::ObjectSerializer
  attributes :id, :user_name, :name, :nickname, :tokens, :created_at

  attributes :user_types do |object|
    object.user_groups
  end
end
