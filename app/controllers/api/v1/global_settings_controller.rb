module Api::V1
	class GlobalSettingsController < ApiController
		before_action :authenticate_user!
		before_action :is_admin_user, :set_global_setting

		def get_chain_limit
			render json: {
				data: {
					chain_limit: @global_setting.value
				}, status: 200
			}
		end

		def set_chain_limit
			if params[:chain_limit].present? && params[:chain_limit] != ""
				if @global_setting.update(value: params[:chain_limit])
					render json: {
						message: "Chain limit changed."
					}, status: 200
				else
					render json: {
						message: "Please try again."
					}, status: 401
				end
			else
				render json: {
					message: "Chain limit can't be blank."
				}, status: 401
			end
		end

		private
		def set_global_setting
			@global_setting = GlobalSetting.find_by(setting: "ChainLimit")
			unless @global_setting
				render json: {
					message: "Chain Limit is not define"
				}, status: 401
			end
		end

		def is_admin_user
			unless current_user.is_admin?
				render json: {message: "You are not allowed" }, status: 401
			end
		end
	end
end