module Api::V1
	class GlobalSettingsController < ApiController
		# before_action :authenticate_user!
		before_action :is_admin_user
		before_action :set_global_setting, only: [:get_chain_limit, :set_chain_limit]

		def get_chain_limit
			render json: {
				data: {
					chain_limit: @global_setting.value
				}, status: 200
			}
		end

		def get_debug_api
			setting = GlobalSetting.find_by(setting: 'debug_api_enabled')
			render json: { data: { debug_api_enabled: setting&.value == 1 } }, status: 200
		end

		def set_debug_api
			setting = GlobalSetting.find_or_create_by(setting: 'debug_api_enabled')
			enabled = params[:enabled] == true || params[:enabled] == 'true' || params[:enabled] == 1
			setting.update(value: enabled ? 1 : 0)
			render json: { message: "Debug API #{enabled ? 'enabled' : 'disabled'}." }, status: 200
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
