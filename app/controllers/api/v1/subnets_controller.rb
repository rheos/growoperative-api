module Api::V1
  # Superuser-only admin surface for subnets. Regular users interact with
  # their own subnet membership via GET /v1/site_config; this controller is
  # for listing all subnets and mutating configs across the deployment.
  class SubnetsController < ApiController
    before_action :require_superuser!

    # GET /v1/subnets
    # Lists every subnet with its current effective flags and member count.
    def index
      subnets = Subnet.includes(:seed_user, :subnet_configs, :subnet_memberships).all
      render json: {
        subnets: subnets.map { |s| subnet_payload(s) }
      }, status: 200
    end

    # GET /v1/subnets/:id/graph
    # Returns { nodes, edges } for rendering the subnet's network map.
    # Intra-subnet relationships + trustlines only — edges crossing subnet
    # boundaries are deliberately excluded so the visualization stays scoped.
    def graph
      subnet = Subnet.find(params[:id])
      member_ids = subnet.subnet_memberships.pluck(:user_id)
      members = User.where(id: member_ids).includes(:user_groups, items: :item_unit)

      nodes = members.map { |u| serialize_graph_node(u) }

      relationships = Relationship.where(user_id: member_ids, friend_id: member_ids)
      rel_edges = relationships.map { |r| { source_id: r.user_id, target_id: r.friend_id, type: 'relationship' } }

      trustlines = Trustline
        .where(user_a_id: member_ids, user_b_id: member_ids)
        .includes(:user_a, :user_b)
        .to_a
      balances = Foaf::GraphBalanceReader.fetch(trustlines)
      if balances.nil?
        return render json: { errors: ['Graph balance data unavailable — FOAF is unreachable'] },
                      status: :service_unavailable
      end
      trust_edges = trustlines.map do |t|
        {
          source_id: t.user_a_id,
          target_id: t.user_b_id,
          type: 'trustline',
          balance: balances.fetch(t.id)
        }
      end

      render json: {
        subnet_id: subnet.id,
        subnet_name: subnet.name,
        nodes: nodes,
        edges: rel_edges + trust_edges
      }, status: 200
    end

    # PATCH /v1/subnets/:id/config
    # Accepts a partial flag hash, merges it over the current config, and
    # writes a NEW SubnetConfig row (subnet_configs is append-only — we never
    # update in place). Returns the subnet's new effective state.
    def update_config
      subnet = Subnet.find(params[:id])
      updates = permitted_flags
      return render json: { message: 'No flags provided' }, status: 422 if updates.empty?

      current = subnet.current_config&.config || {}
      next_config = current.merge(updates.stringify_keys)

      SubnetConfig.create!(
        subnet: subnet,
        version: subnet.next_config_version,
        config: next_config,
        changed_by_user_id: current_user.id
      )

      render json: subnet_payload(subnet.reload), status: 200
    end

    private

    def require_superuser!
      return if current_user&.is_superuser?
      render json: { message: 'Superuser access required' }, status: 403
    end

    def permitted_flags
      SiteConfig.permit_flags(params)
    end

    def serialize_graph_node(user)
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

    def subnet_payload(subnet)
      {
        id: subnet.id,
        name: subnet.name,
        seed_user_name: subnet.seed_user&.user_name,
        member_count: subnet.subnet_memberships.size,
        config: SiteConfig.for(subnet),
        stored_config: subnet.current_config&.config,
        version: subnet.current_config&.version
      }
    end
  end
end
