class Api::V1::HomeController < Api::V1::ApiController
  skip_before_action :authenticate!, except: [:available_user_type]

  def root
    render json: {
      status: 'ok',
      api_version: 'v1',
      environment: Rails.env,
      timestamp: Time.current,
      endpoints: {
        base_url: '/api/v1',
        auth: '/api/v1/login',
        items: '/api/v1/items',
        users: '/api/v1/users'
      }
    }
  end

	def verify_invitation_code
		@invitation = Invitation.find_by(invitation_code: params[:invitation_token])
		if @invitation
			if @invitation.pending?
				render json: {invitation_token: params[:invitation_token]},staus: 200
			elsif @invitation.accepted?
				render json: {
					message: "Invitation code is already used"
				}, status: 422
			end
		else
			render json: {message: "Invalid Invitation code"}, status: 422
		end
	end

	# This method will return user types of current user will have permission
	# url : /v1/available_user_type
	# method : GET
	def available_user_type
		user_groups = current_user.user_groups
		avilable_type = []
		user_groups.each do |user_group|
			case user_group.group_label
			when "admin"
				# avilable_type += ["producer", "broker", "wholesaler", "retailer", "consumer", "admin"]
				avilable_type += ["producer", "broker", "wholesaler", "retailer", "admin", "consumer"]
			when "consumer"
				avilable_type += ["consumer"]
			when "producer"
				avilable_type += ["producer"]
			when "broker"
				# avilable_type += ["producer", "broker", "wholesaler", "retailer", "consumer"]
				avilable_type += ["producer", "broker", "wholesaler"]
			when "retailer"
				avilable_type += ["consumer"]
			when "wholesaler"
				# avilable_type += ["producer", "retailer"]
				avilable_type += ["producer"]
			end
		end
		render json: {
			available_types: avilable_type.uniq
		}, status: 200
	end
end
