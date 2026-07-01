module Api::V1
  # Local discovery: opt-in "who's near me" over the mutual-credit network.
  #
  # AC 15 privacy invariant governs every decision here about what is stored
  # vs returned. Raw coordinates are quantised to a fixed grid cell centroid
  # (Discovery::GridSnap) before they ever hit the database, are never echoed
  # back to the client, and are filtered out of request logs
  # (config/initializers/filter_parameter_logging.rb). Only the coarse cell
  # centroid is stored and exposed.
  #
  # Plain-hash JSON, no serializer (mirrors NotificationsController). The
  # parent ApiController runs `before_action :authenticate!`, so an
  # unauthenticated request 401s before any action body runs.
  class DiscoveryController < ApiController
    ALLOWED_RADII_KM = [5, 10, 25, 50, 100].freeze

    # PATCH /v1/discovery/location
    #
    # Params: { latitude, longitude } (numerics).
    #
    # Snap the raw input to its grid-cell centroid and store that. The raw
    # coordinate is never persisted and never reflected — the response echoes
    # the stored centroid, so it can never leak a sub-cell point (AC 15
    # defense-in-depth). Capture is decoupled from visibility (Decision C):
    # this endpoint is available regardless of location_opted_in, so a
    # browse-only user stores a centroid without becoming discoverable.
    def update_location
      cell_lat, cell_lng = Discovery::GridSnap.snap(params[:latitude], params[:longitude])
      current_user.latitude = cell_lat
      current_user.longitude = cell_lng
      current_user.location_updated_at = Time.current

      if current_user.save
        render json: { cell_lat: current_user.latitude.to_f, cell_lng: current_user.longitude.to_f }
      else
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /v1/discovery/settings
    #
    # Params: { opted_in?, radius_km? }.
    #
    # - opted_in maps to location_opted_in (boolean or 'true'/'false' string).
    # - radius_km must be in ALLOWED_RADII_KM; 422 with a clear message otherwise.
    # - Opt-out (opted_in: false) must NOT clear coordinates (FR 13) — capture
    #   and visibility are independent.
    # Last-write-wins.
    def update_settings
      if params.key?(:opted_in)
        current_user.location_opted_in = ActiveModel::Type::Boolean.new.cast(params[:opted_in])
      end

      if params.key?(:radius_km)
        radius = params[:radius_km].to_i
        unless ALLOWED_RADII_KM.include?(radius)
          return render json: {
            errors: ["radius_km must be one of #{ALLOWED_RADII_KM.join(', ')}"]
          }, status: :unprocessable_entity
        end
        current_user.discovery_radius_km = radius
      end

      if current_user.save
        render json: {
          location_opted_in: current_user.location_opted_in,
          discovery_radius_km: current_user.discovery_radius_km
        }
      else
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # GET /v1/discovery/nearby
    #
    # Origin is ALWAYS the caller's own stored centroid — no coordinate is
    # accepted from the request (AC 15a). A caller with no stored centroid
    # gets the enable-state payload { origin_cell: nil, members: [] }, from
    # which the client renders "share your location to see who's nearby".
    def nearby
      if current_user.latitude.nil? || current_user.longitude.nil?
        return render json: { origin_cell: nil, members: [] }
      end

      origin_lat = current_user.latitude.to_f
      origin_lng = current_user.longitude.to_f
      radius_km  = (current_user.discovery_radius_km || 25).to_i
      staleness  = GlobalSetting.find_by(setting: 'DiscoveryStalenessDays')&.value.to_i
      staleness  = 30 if staleness.nil? || staleness.zero?
      cutoff     = staleness.days.ago

      # Bounding-box prefilter — rides the composite [latitude, longitude]
      # index from Prompt 1 so the DB narrows the set before the finer
      # sphere-distance sort runs.
      lat_delta = radius_km / 111.0
      cos_lat   = [Math.cos(origin_lat * Math::PI / 180.0), 0.0001].max
      lng_delta = radius_km / (111.0 * cos_lat)

      base = User.auth_active                                   # deleted_at: nil, disabled_at: nil
                 .includes(:user_groups)                        # preloads roles — no N+1 in member_json
                 .where.not(id: current_user.id)
                 .where(location_opted_in: true)
                 .where('location_updated_at > ?', cutoff)
                 .where('latitude  BETWEEN ? AND ?', origin_lat - lat_delta, origin_lat + lat_delta)
                 .where('longitude BETWEEN ? AND ?', origin_lng - lng_delta, origin_lng + lng_delta)

      # Same-demo scoping (user.rb:56/59): demo users see only demo users;
      # real users never see demo users.
      base = current_user.demo? ? base.where(id: User.demo.select(:id)) : base.where.not(id: User.demo.select(:id))

      # Centroid-to-centroid great-circle distance, in km. Sanitized SQL so
      # the origin coordinates can never be an injection vector.
      # ST_Distance_Sphere(POINT(lng, lat), ...) — longitude first, latitude second.
      sql_dist = ActiveRecord::Base.sanitize_sql_array(
        ['ST_Distance_Sphere(POINT(longitude, latitude), POINT(?, ?)) / 1000.0', origin_lng, origin_lat]
      )

      members = base
                .select('users.*', Arel.sql("#{sql_dist} AS distance_km"))
                .sort_by(&:distance_km)
                .select { |u| u.distance_km.to_f <= radius_km }

      render json: {
        origin_cell: { cell_lat: origin_lat, cell_lng: origin_lng },
        members: members.map { |u| member_json(u) }
      }
    end

    private

    # Discovery-facing member card. No precise coordinate ever appears here:
    # cell_lat/cell_lng are the stored centroids (already coarse, snapped on
    # the /location write). role_label is the first non-meta group_label
    # (demo/superuser filtered out).
    def member_json(user)
      non_meta = user.user_groups.reject { |g| %w[demo superuser].include?(g.group_label) }
      role_label = non_meta.first&.group_label
      {
        id:           user.id,
        foaf_id:      user.foaf_id,
        display_name: user.display_name.presence || user.user_name,
        avatar_url:   user.avatar_url,
        role:         role_label,
        distance_km:  user.distance_km.to_f,
        cell_lat:     user.latitude.to_f,
        cell_lng:     user.longitude.to_f
      }
    end
  end
end
