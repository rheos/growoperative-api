class Api::V1::DemoController < Api::V1::ApiController
  skip_before_action :authenticate!, only: [:users, :login, :setup]

  CORE_DEMO_USERNAMES = %w[bob dianna peter paul sara mary bruce arthur clark oliver barry mark john].freeze

  # GET /v1/demo/users
  # Returns graph data (nodes + edges) for the demo network map
  def users
    demo_users = User.where(user_name: CORE_DEMO_USERNAMES)
                     .includes(:user_groups, items: :item_unit)
    demo_ids = demo_users.pluck(:id)

    nodes = demo_users.map { |u| serialize_node(u) }

    # Edges from relationships between demo users
    relationships = Relationship.where(user_id: demo_ids, friend_id: demo_ids)
    rel_edges = relationships.map do |r|
      { source_id: r.user_id, target_id: r.friend_id, type: 'relationship' }
    end

    # Edges from trustlines between demo users
    trustlines = Trustline.where(user_a_id: demo_ids, user_b_id: demo_ids)
    trust_edges = trustlines.map do |t|
      { source_id: t.user_a_id, target_id: t.user_b_id, type: 'trustline', balance: t.current_balance.to_f }
    end

    # The map uses multi_role to decide whether to show per-node role badges and
    # the role-color legend. Reads from the seed demo user's primary subnet
    # (Bob's Network); falls back to the SiteConfig default if unresolvable.
    seed_user = demo_users.find { |u| u.user_name == 'bob' } || demo_users.first
    subnet = seed_user&.primary_subnet
    multi_role = SiteConfig.for(subnet)[:multi_role]

    render json: { nodes: nodes, edges: rel_edges + trust_edges, multi_role: multi_role }
  end

  # POST /v1/demo/login
  # Passwordless login for demo users only. Job 42: proxies to
  # auth.foaf.io's POST /v1/internal/demo_tokens (Job 29). The auth
  # service must have DEMO_TOKEN_ISSUER_ENABLED=true and the user's
  # foaf_id must be in the source-controlled demo allowlist.
  def login
    user = User.demo.find_by(id: params[:user_id])
    return render json: { error: 'Demo user not found' }, status: :not_found unless user

    if user.foaf_id.blank?
      Rails.logger.error("Demo login refused: user_id=#{user.id} has no foaf_id")
      return render json: { error: 'Demo user is not provisioned for v1 auth' }, status: :unprocessable_entity
    end

    status, body = AuthFoafClient.demo_token(foaf_id: user.foaf_id)
    if status != 200 || body['token'].blank?
      Rails.logger.error("Demo login proxy failed: status=#{status} body=#{body.inspect}")
      return render json: { error: 'Demo token issuance failed' }, status: :bad_gateway
    end

    clear_legacy_jwt_cookie!
    render json: UserSerializer.new(user).serializable_hash.merge(
      token: body['token'],
      identity: identity_payload(user),
    ), status: 200
  end

  # POST /v1/demo/setup
  # One-time bootstrap: mark demo users, create superuser, take snapshot.
  # Controlled by GlobalSetting 'demo_setup_enabled' — disable after use.
  def setup
    setting = GlobalSetting.find_or_create_by!(setting: 'demo_setup_enabled') { |s| s.value = 1 }
    unless setting.value == 1
      return render json: { error: 'Setup endpoint is disabled. Set demo_setup_enabled=1 in global_settings to re-enable.' }, status: :forbidden
    end

    results = []

    # 1. Mark demo users
    count = 0
    CORE_DEMO_USERNAMES.each do |name|
      user = User.find_by(user_name: name)
      if user
        user.user_groups.find_or_create_by!(group_label: :demo)
        count += 1
      end
    end
    results << "Marked #{count} demo users"

    # 2. Create superuser if params provided
    if params[:superuser_name].present? && params[:superuser_password].present?
      su = User.find_by(user_name: params[:superuser_name])
      if su
        su.user_groups.find_or_create_by!(group_label: :superuser)
        results << "Added superuser group to existing user '#{params[:superuser_name]}'"
      else
        su = User.new(
          user_name: params[:superuser_name],
          password: params[:superuser_password],
          invite_limit: 0,
          depth: 0,
          invitations_count: 0,
        )
        su.save!(validate: false)
        su.update_columns(invitation_limit: 0)
        su.user_groups.create!(group_label: :superuser)
        results << "Created superuser '#{params[:superuser_name]}'"
      end
    end

    # 3. Capture snapshot
    DemoSnapshotService.new.capture
    results << "Snapshot saved"

    # 4. Disable this endpoint
    setting.update!(value: 0)
    results << "Setup endpoint disabled"

    render json: { message: results.join('. ') }
  rescue StandardError => e
    Rails.logger.error("Demo setup failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { error: "Setup failed: #{e.message}" }, status: :internal_server_error
  end

  # POST /v1/demo/reset
  # Reset demo data from snapshot (superuser only)
  def reset
    unless current_user&.superuser?
      return render json: { error: 'Forbidden' }, status: :forbidden
    end

    snapshot_name = params[:snapshot_name] || 'default'
    DemoResetService.new(
      snapshot_name: snapshot_name,
      actor_user: current_user,
      source: 'api',
    ).call
    render json: { message: "Demo data reset to '#{snapshot_name}'" }
  rescue StandardError => e
    Rails.logger.error("Demo reset failed: #{e.message}")
    render json: { error: "Reset failed: #{e.message}" }, status: :internal_server_error
  end

  # GET /v1/demo/snapshots
  # List available snapshots (superuser only)
  def snapshots
    unless current_user&.superuser?
      return render json: { error: 'Forbidden' }, status: :forbidden
    end

    render json: DemoSnapshotService.list
  end

  # POST /v1/demo/snapshot
  # Save current demo state as a named snapshot (superuser only)
  def save_snapshot
    unless current_user&.superuser?
      return render json: { error: 'Forbidden' }, status: :forbidden
    end

    name = params[:name]
    if name.blank?
      return render json: { error: 'Snapshot name is required' }, status: :unprocessable_entity
    end

    include_requests = params[:include_requests] != false && params[:include_requests] != 'false'
    DemoSnapshotService.new(name: name, include_requests: include_requests).capture
    render json: { message: "Snapshot '#{name}' saved" }
  rescue StandardError => e
    Rails.logger.error("Snapshot save failed: #{e.message}")
    render json: { error: "Save failed: #{e.message}" }, status: :internal_server_error
  end

  private

  def serialize_node(user)
    roles = user.user_groups.map(&:group_label).reject { |g| g == 'demo' }
    {
      id: user.id,
      user_name: user.user_name,
      name: user.name || user.user_name.capitalize,
      roles: roles,
      parent_id: user.parent_id,
      depth: user.depth || 0,
      items: user.items.map { |i| "#{i.quantity.to_i}#{i.item_unit&.item_symbol} #{i.name}" }
    }
  end
end
