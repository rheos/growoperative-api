module Api::V1
  module Admin
    # Superuser-only admin invitations. Currently exposes the "seed code"
    # primitive: an invitation that, when redeemed at signup, mints a brand
    # new Subnet with the redeemer as seed_user (instead of joining the
    # inviter's subnet). The inviter still becomes the new user's parent in
    # the invite tree — this decouples the invite graph from the subnet
    # graph deliberately.
    class InvitationsController < ApiController
      before_action :require_superuser!

      # GET /v1/admin/invitations/seed
      # Returns the current admin's seed invitations (those with a
      # subnet_seed_config), newest first. Read-only inventory for the
      # "what have I already created?" view in the admin tool.
      def list_seed
        invitations = current_user.invitations
          .where.not(subnet_seed_config: nil)
          .order(created_at: :desc)

        render json: invitations.map { |inv| serialize(inv) }, status: 200
      end

      # POST /v1/admin/invitations/seed
      # Body:
      #   subnet_name:        "Kaslo Network"        (required)
      #   user_type:          "broker" | ...         (optional, defaults to broker)
      #   chain_limit:        5                       (optional)
      #   default_markup:     10                      (optional)
      #   default_markup_type:"percent" | "flat"      (optional)
      #   visible_roles:      ["broker", ...]         (optional)
      #   multi_role:         false                   (optional)
      #   enforce_valid_email:false                   (optional)
      #
      # Returns the invitation including its code. The redeeming user becomes
      # seed_user of a new Subnet with these flags written as SubnetConfig v1.
      def create_seed
        subnet_name = params[:subnet_name].to_s.strip
        return render json: { message: 'subnet_name is required' }, status: 422 if subnet_name.blank?

        config_payload = permitted_flags
        seed_payload = {
          'subnet_name' => subnet_name,
          'config' => config_payload
        }

        invitation = current_user.invitations.new(
          status: :pending,
          user_type: permitted_user_type,
          subnet_seed_config: seed_payload
        )

        # Mint a pronounceable code from auth.foaf.io (CVCV-CVCV "mavo-leni")
        # so seed codes look the same as normal invite codes. Without this
        # the model's local before_create generator emits an easy random
        # alphanumeric instead. Fall through to that local generator on any
        # auth.foaf.io failure so transient blips don't kill the mint UX.
        invitation.invitation_code = pronounceable_code_or_nil(current_user)

        if invitation.save
          render json: serialize(invitation), status: 201
        else
          render json: { errors: invitation.errors.full_messages }, status: 422
        end
      end

      private

      def pronounceable_code_or_nil(inviter)
        return nil if inviter.foaf_id.blank?

        auth_status, auth_body = AuthFoafClient.create_invitation(
          inviter_foaf_id: inviter.foaf_id,
          target_app: 'growoperative'
        )
        return auth_body['code'] if auth_status == 201 && auth_body['code'].present?

        Rails.logger.warn(
          "auth.foaf.io invite mint returned status=#{auth_status}; falling back to local random code"
        )
        nil
      rescue StandardError => e
        Rails.logger.warn(
          "auth.foaf.io invite mint failed (#{e.class}: #{e.message}); falling back to local random code"
        )
        nil
      end

      def require_superuser!
        return if current_user&.is_superuser?
        render json: { message: 'Superuser access required' }, status: 403
      end

      # Mirrors the whitelist from SubnetsController#permitted_flags so the
      # admin endpoint and the per-subnet config-update endpoint accept the
      # same shape.
      def permitted_flags
        allowed = {}
        if params.key?(:multi_role)
          allowed['multi_role'] = to_bool(params[:multi_role])
        end
        if params.key?(:enforce_valid_email)
          allowed['enforce_valid_email'] = to_bool(params[:enforce_valid_email])
        end
        if params.key?(:visible_roles)
          roles = Array(params[:visible_roles]).map(&:to_s).reject(&:empty?)
          allowed['visible_roles'] = roles
        end
        if params.key?(:chain_limit) && params[:chain_limit].present?
          allowed['chain_limit'] = params[:chain_limit].to_i
        end
        if params.key?(:default_markup) && params[:default_markup].present?
          allowed['default_markup'] = params[:default_markup].to_f
        end
        if params.key?(:default_markup_type) && params[:default_markup_type].present?
          type = params[:default_markup_type].to_s
          allowed['default_markup_type'] = Markup::TYPES.include?(type) ? type : 'flat'
        end
        allowed
      end

      def permitted_user_type
        return params[:user_type] if Invitation.user_types.key?(params[:user_type].to_s)
        'broker'
      end

      def to_bool(v)
        return v if v == true || v == false
        %w[true 1 yes].include?(v.to_s.downcase)
      end

      def serialize(invitation)
        {
          id: invitation.id,
          invitation_code: invitation.invitation_code,
          user_type: invitation.user_type,
          status: invitation.status,
          subnet_seed_config: invitation.subnet_seed_config,
          inviter_user_name: invitation.user&.user_name,
          label: invitation.label,
          created_at: invitation.created_at&.iso8601,
          accepted_id: invitation.accepted_id,
          accepted_user_name: invitation.accepted_id ? User.find_by(id: invitation.accepted_id)&.user_name : nil
        }
      end
    end
  end
end
