class Api::V1::DemoController < Api::V1::ApiController
  skip_before_action :authenticate!, only: [:users, :login]

  CORE_DEMO_USERNAMES = %w[bob dianna peter paul sara mary bruce arthur clark oliver barry mark john].freeze

  # GET /v1/demo/users
  # Returns graph data (nodes + edges) for the demo network map
  def users
    demo_users = User.where(user_name: CORE_DEMO_USERNAMES)
                     .includes(:user_groups)
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

    render json: { nodes: nodes, edges: rel_edges + trust_edges }
  end

  # POST /v1/demo/login
  # Passwordless login for demo users only
  def login
    user = User.demo.find_by(id: params[:user_id])
    if user
      assign_jwt_cookies(user)
      render json: UserSerializer.new(user), status: 200
    else
      render json: { error: 'Demo user not found' }, status: :not_found
    end
  end

  # POST /v1/demo/reset
  # Reset demo data from snapshot (admin only)
  def reset
    unless current_user&.is_admin?
      return render json: { error: 'Forbidden' }, status: :forbidden
    end

    DemoResetService.new.call
    render json: { message: 'Demo data reset successfully' }
  rescue StandardError => e
    Rails.logger.error("Demo reset failed: #{e.message}")
    render json: { error: "Reset failed: #{e.message}" }, status: :internal_server_error
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
      depth: user.depth || 0
    }
  end
end
