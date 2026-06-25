module Api::V1
  class PushTokensController < ApiController
    def create
      device_id = params.require(:device_id)
      token     = params.require(:token)
      platform  = params.require(:platform)

      # Try to find by (user, device) first — rotation/reinstall path.
      row = current_user.push_tokens.find_by(device_id: device_id)

      if row
        row.update!(token: token, last_seen_at: Time.current)
      else
        # Ownership-transfer: if token already exists for another user, claim it.
        row = PushToken.find_by(token: token)
        if row
          row.update!(user_id: current_user.id, device_id: device_id, last_seen_at: Time.current)
        else
          current_user.push_tokens.create!(
            token:        token,
            device_id:    device_id,
            platform:     platform,
            last_seen_at: Time.current
          )
        end
      end

      head :no_content
    rescue ActiveRecord::RecordInvalid => e
      # Invalid param (e.g. platform not in ios/android) → 422, not an unhandled 500.
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def destroy
      device_id = params.require(:device_id)
      current_user.push_tokens.where(device_id: device_id).destroy_all
      head :no_content
    end
  end
end
