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
    ALLOWED_RADII_KM = [2, 5, 10, 25, 50, 100].freeze

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
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_content
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
          }, status: :unprocessable_content
        end
        current_user.discovery_radius_km = radius
      end

      if current_user.save
        render json: {
          location_opted_in: current_user.location_opted_in,
          discovery_radius_km: current_user.discovery_radius_km
        }
      else
        render json: { errors: current_user.errors.full_messages }, status: :unprocessable_content
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
      radius_km  = (current_user.discovery_radius_km || 5).to_i
      # Freshness window: hide members whose last location share is older than
      # this. Tunable at runtime via the DiscoveryStalenessDays GlobalSetting;
      # defaults to 90 days when unset. (Was 30, which silently hid every
      # opted-in member once nothing refreshed their location — see issue #42.)
      staleness  = GlobalSetting.find_by(setting: 'DiscoveryStalenessDays')&.value.to_i
      staleness  = 90 if staleness.nil? || staleness.zero?
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

      # Centroid-to-centroid great-circle distance, in km. Raw haversine formula in plain SQL —
      # no PostGIS extension required (works on Neon as-is). Sanitized SQL so the origin
      # coordinates can never be an injection vector.
      # Haversine: 6371 * 2 * asin(sqrt(sin²(Δlat/2) + cos(lat1)*cos(lat2)*sin²(Δlng/2)))
      # Args (in order of ? placeholders): origin_lat, origin_lat, origin_lng
      sql_dist = ActiveRecord::Base.sanitize_sql_array(
        [
          '6371.0 * 2 * asin(sqrt(' \
            'power(sin(radians(latitude - ?) / 2), 2) + ' \
            'cos(radians(?)) * cos(radians(latitude)) * power(sin(radians(longitude - ?) / 2), 2)' \
          '))',
          origin_lat, origin_lat, origin_lng
        ]
      )

      members = base
                .select('users.*', Arel.sql("#{sql_dist} AS distance_km"))
                .sort_by(&:distance_km)
                .select { |u| u.distance_km.to_f <= radius_km }

      # Mutual contacts — flag-gated, privacy-critical (scope-brief §"Mutual
      # contacts"). When SiteConfig[:show_mutual_contacts] is off there is ZERO
      # computation and ZERO mutual data on the payload. When on, we return only
      # the INTERSECTION of the caller's accepted contacts with each member's
      # accepted contacts — never either party's full contact list.
      #
      # Query budget: at most 3 queries (my_ids pluck + cross fetch + faces
      # load) regardless of member count — no N+1 (locked by a query-count
      # spec). The faces load reapplies the SAME-DEMO boundary the `base` query
      # uses (see :109 above) so a cross-demo mutual contact can never surface,
      # even though the Relationship row is valid on each side individually.
      mutual_by_member = compute_mutual_contacts(members) if mutual_contacts_flag?
      mutual_by_member ||= {}

      render json: {
        origin_cell: { cell_lat: origin_lat, cell_lng: origin_lng },
        members: members.map { |u| member_json(u, mutual_faces: mutual_by_member[u.id]) }
      }
    end

    private

    # Resolve the caller's subnet flag. Subnet resolution mirrors
    # site_configs_controller.rb:19–26 (primary membership, then any). A caller
    # with no subnet falls through to SiteConfig::DEFAULTS (flag default true).
    def mutual_contacts_flag?
      subnet = current_user.subnet_memberships.primary.first&.subnet ||
               current_user.subnet_memberships.first&.subnet
      SiteConfig.for(subnet)[:show_mutual_contacts]
    end

    # Build { member_id => [User, …] } of the mutual accepted contacts shared
    # between the caller and each nearby member. Returns only the intersection,
    # never a full contact list, and applies the SAME-DEMO boundary to the face
    # load so no cross-demo contact leaks. At most 3 SQL queries total,
    # independent of member count (no N+1).
    def compute_mutual_contacts(members)
      result = {}
      return result if members.empty?

      me         = current_user
      member_ids = members.map(&:id)

      # (1) My accepted contacts — one query, both directions.
      my_ids = Relationship.where(status: :accepted)
                           .where('user_id = :me OR friend_id = :me', me: me.id)
                           .pluck(:user_id, :friend_id)
                           .flatten
                           .reject { |id| id == me.id }
                           .uniq
      return result if my_ids.empty?

      # (2) Accepted relationships crossing (member set × my contacts) — one query.
      cross = Relationship.where(status: :accepted)
                          .where(
                            '(user_id IN (:members) AND friend_id IN (:mine)) OR ' \
                            '(user_id IN (:mine) AND friend_id IN (:members))',
                            members: member_ids, mine: my_ids
                          )

      member_set = member_ids.to_set
      mine_set   = my_ids.to_set
      raw_map    = Hash.new { |h, k| h[k] = [] }
      # Check both directions independently. When two nearby members are both
      # my contacts and know each other (a triangle), one row makes each the
      # other's mutual; an elsif credited only the lower-id side.
      cross.each do |rel|
        if member_set.include?(rel.user_id) && mine_set.include?(rel.friend_id)
          raw_map[rel.user_id] << rel.friend_id
        end
        if member_set.include?(rel.friend_id) && mine_set.include?(rel.user_id)
          raw_map[rel.friend_id] << rel.user_id
        end
      end
      return result if raw_map.empty?

      # (3) Load faces for every mutual contact id in one query, reapplying the
      # SAME-DEMO boundary from the `base` query (discovery_controller.rb:109):
      # a real user's contact who is a demo user (or vice-versa) is excluded
      # here, so a cross-demo mutual can never appear even though the
      # Relationship rows are individually valid.
      all_mutual_ids = raw_map.values.flatten.uniq
      faces_scope = User.auth_active.where(id: all_mutual_ids)
      faces_scope = me.demo? ? faces_scope.where(id: User.demo.select(:id)) : faces_scope.where.not(id: User.demo.select(:id))
      faces = faces_scope.index_by(&:id)

      raw_map.each do |member_id, contact_ids|
        result[member_id] = contact_ids.uniq.filter_map { |cid| faces[cid] }
      end
      result
    end

    # Discovery-facing member card. No precise coordinate ever appears here:
    # cell_lat/cell_lng are the stored centroids (already coarse, snapped on
    # the /location write). role_label is the first non-meta group_label
    # (demo/superuser filtered out). member_since is created_at.year (a bare
    # integer, no coordinate). mutual (when present) carries only
    # {id, name, avatar_url} — no coordinate. AC-15 invariant preserved.
    def member_json(user, mutual_faces: nil)
      non_meta = user.user_groups.reject { |g| %w[demo superuser].include?(g.group_label) }
      role_label = non_meta.first&.group_label
      hash = {
        id:           user.id,
        foaf_id:      user.foaf_id,
        display_name: user.display_name.presence || user.user_name,
        avatar_url:   user.avatar_url,
        role:         role_label,
        about:        user.about,
        area_label:   user.area_label,
        offering:     user.offering,
        distance_km:  user.distance_km.to_f,
        cell_lat:     user.latitude.to_f,
        cell_lng:     user.longitude.to_f,
        member_since: user.created_at.year
      }
      if mutual_faces
        hash[:mutual] = mutual_faces.map do |u|
          { id: u.id, name: u.display_name.presence || u.user_name, avatar_url: u.avatar_url }
        end
      end
      hash
    end
  end
end
