class UserSerializer
  include JSONAPI::Serializer
  attributes :id, :user_name, :name, :nickname, :tokens, :created_at, :invite_limit

  # Discovery visibility + radius ride the user payload so the client can seed
  # its settings on session start (Account Settings shows server truth). The
  # stored centroid is deliberately NOT serialized here — AC 15 exposes cells
  # only through the discovery endpoints.
  attributes :location_opted_in, :discovery_radius_km

  # Enriched profiles: app-owned "what I grow/sell" blurb (Plan 30), so the
  # profile + update_profile responses carry it for the editor + own-profile view.
  attributes :offering

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
