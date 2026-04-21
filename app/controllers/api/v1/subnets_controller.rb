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

    # Whitelist the flags the admin UI is allowed to set. Expanded cautiously —
    # anything not here is silently ignored.
    def permitted_flags
      allowed = {}
      if params.key?(:multi_role)
        allowed[:multi_role] = to_bool(params[:multi_role])
      end
      if params.key?(:visible_roles)
        roles = Array(params[:visible_roles]).map(&:to_s).reject(&:empty?)
        allowed[:visible_roles] = roles
      end
      if params.key?(:chain_limit) && params[:chain_limit].present?
        allowed[:chain_limit] = params[:chain_limit].to_i
      end
      allowed
    end

    def to_bool(v)
      return v if v == true || v == false
      %w[true 1 yes].include?(v.to_s.downcase)
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
