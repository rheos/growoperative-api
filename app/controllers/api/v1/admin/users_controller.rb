module Api::V1
  module Admin
    class UsersController < ApiController
      before_action :require_superuser!

      DEFAULT_LIMIT = 20
      MAX_LIMIT = 50

      def index
        query = params[:q].to_s.strip
        status, body = AuthFoafClient.search_users(
          query: query,
          limit: result_limit,
          include_deleted: include_deleted?
        )
        result_count = status == 200 ? Array(body['matches']).length : 0
        audit('admin.users.search', { query: query, result_count: result_count })
        render_downstream(status, body)
      rescue StandardError => e
        Rails.logger.error("admin user search failed: #{e.class}: #{e.message}")
        audit('admin.users.search', { query: params[:q].to_s, result_count: 0 }, status: 'failed')
        render json: { error: 'admin user search failed' }, status: :bad_gateway
      end

      def show
        foaf_id = params[:foaf_id].to_s
        status, body = AuthFoafClient.get_user(foaf_id: foaf_id)
        audit('admin.users.view', { target_foaf_id: foaf_id }, status: status == 200 ? 'succeeded' : 'failed')

        return render_downstream(status, body) unless status == 200

        render json: {
          identity: body['identity'],
          profile: profile_payload(User.find_by(foaf_id: foaf_id))
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("admin user detail failed: #{e.class}: #{e.message}")
        audit('admin.users.view', { target_foaf_id: params[:foaf_id].to_s }, status: 'failed')
        render json: { error: 'admin user detail failed' }, status: :bad_gateway
      end

      def reset_password
        foaf_id = params[:foaf_id].to_s
        new_password = params[:new_password].to_s
        if new_password.length < 8
          return render json: { error: 'password must be at least 8 characters' }, status: :unprocessable_entity
        end

        target_identity = identity_for_audit(foaf_id)
        status, body = AuthFoafClient.admin_reset_password(
          foaf_id: foaf_id,
          new_password: new_password
        )

        if status == 200
          audit('admin.users.reset_password', {
            target_foaf_id: foaf_id,
            target_user_name: target_identity && target_identity['user_name'],
            tokens_invalid_before: body['tokens_invalid_before']
          })
        else
          audit('admin.users.reset_password', { target_foaf_id: foaf_id }, status: 'failed')
        end

        render_downstream(status, body)
      rescue StandardError => e
        Rails.logger.error("admin password reset failed: #{e.class}: #{e.message}")
        audit('admin.users.reset_password', { target_foaf_id: params[:foaf_id].to_s }, status: 'failed')
        render json: { error: 'admin password reset failed' }, status: :bad_gateway
      end

      private

      def require_superuser!
        return if current_user&.is_superuser? && !current_user.demo?
        render json: { error: 'forbidden' }, status: :forbidden
      end

      def result_limit
        raw = params[:limit].presence || DEFAULT_LIMIT
        [[raw.to_i, 1].max, MAX_LIMIT].min
      end

      def include_deleted?
        ActiveModel::Type::Boolean.new.cast(params[:include_deleted]) == true
      end

      def render_downstream(status, body)
        if status.to_i.between?(200, 299)
          render json: body, status: status
        else
          render json: {
            error: body['error'] || body['message'] || 'auth service request failed'
          }, status: status
        end
      end

      def identity_for_audit(foaf_id)
        status, body = AuthFoafClient.get_user(foaf_id: foaf_id)
        status == 200 ? body['identity'] : nil
      rescue StandardError
        nil
      end

      def audit(action, metadata, status: 'succeeded')
        AuditLog.record(
          action: action,
          actor_user: current_user,
          source: 'api',
          status: status,
          metadata: metadata
        )
      end

      def profile_payload(user)
        return nil unless user

        memberships = user.subnet_memberships.includes(:subnet).map do |membership|
          {
            id: membership.id,
            subnet_id: membership.subnet_id,
            subnet_name: membership.subnet&.name,
            is_primary: membership.is_primary
          }
        end
        labels = user.user_groups.pluck(:group_label)

        {
          growoperative_user_id: user.id,
          user_name: user.user_name,
          display_name: user.display_name,
          roles: labels,
          is_admin: labels.include?('admin') || labels.include?('superuser'),
          is_superuser: labels.include?('superuser'),
          is_demo: labels.include?('demo'),
          invite_limit: {
            remaining: user.ramaining_invitation_limit,
            total: user.invite_limit
          },
          created_at: user.created_at&.iso8601,
          subnet_memberships: memberships,
          item_count: user.items.count,
          last_seen_at: (user.current_sign_in_at || user.last_sign_in_at)&.iso8601
        }
      end
    end
  end
end
