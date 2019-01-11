module Api::V1
	class InvitationsController < ApiController
		before_action :authenticate_user!
		before_action :set_invitation, only: [:update]
		# This api will return all invitation code of login user
		# url : v1/invitations
		# method : GET
		def index
			@invitations = current_user.invitations.joins('LEFT JOIN users ON users.id = invitations.accepted_id').select("invitations.*, users.nickname").to_a
			
			@invitations.each do |invitation|
				if invitation.accepted_id
					relation = Relationship.where("user_id IN (?) AND friend_id IN (?)", [current_user.id, invitation.accepted_id], [current_user.id, invitation.accepted_id])
					if relation.first
						if (relation.first.user_id == current_user.id) && relation.first.friend_label?
							invitation.note_label = relation.first.friend_label
						elsif (relation.first.friend_id == current_user.id) && relation.first.user_label?
							invitation.note_label = relation.first.user_label
						elsif User.find_by(id: invitation.accepted_id).nickname?
							invitation.note_label = User.find_by(id: invitation.accepted_id).nickname
						else
							invitation.note_label = User.find_by(id: invitation.accepted_id).user_name
						end
					end
				end
			end

			render json: {
				data: @invitations
			}
		end

		# This api will update label
		# url : v1/invitations/:id
		# method : POST
		# parameter : { "invitation": {"label": "Demo"}}
		def update
			if @invitation.update(invitation_params)
				render json: {
					data: @invitation,
					message: "Invitation update successfully"
				}, status: 200
			else
				render json: @invitation.errors, status: 422
			end
		end
		
		# This api will update user_type
		# url : v1/invitations/:id/set_user_type
		# method : PUT
		# parameter :  {"user_type": "Demo"}
		def set_user_type
			@invitation = current_user.invitations.find_by(id: params[:invitation_id])
			unless @invitation
				render json: {
					message: "You are not authorised to access."
				}, status: 422
				return
			end
			if params[:user_type].present? &&  params[:user_type] != ''
				if @invitation.update user_type: params[:user_type]
					render json: {
						message: "User type set successfully."
					}, status: 200
				else
					render json: @invitation.errors, status: 422
				end
			else
				render json: {
					message: "Please enter proper value"
				}, status: 422
			end
		end

		# This api will set note_label
		# url : /v1/invitations/:invitation_id/set_note_label
		# method : PUT
		# parameter :  {"note_label": "Demo"}
		def set_note_label
			@invitation = current_user.invitations.find_by(id: params[:invitation_id])
			unless @invitation
				render json: {
					message: "You are not authorised to access."
				}, status: 422
				return
			end
			if params[:note_label].present? &&  params[:note_label] != ''
				if @invitation.update note_label: params[:note_label]
					render json: {
						message: "Note label set successfully."
					}, status: 200
				else
					render json: @invitation.errors, status: 422
				end
			else
				render json: {
					message: "Please enter proper value"
				}, status: 422
			end
		end

		# This method will return user info if code is used 
		# url : /v1/invitations/user_info
		# method : Patch
		# parametet: {code: "code"}
		def user_info
			@invitation = Invitation.find_by(invitation_code: params[:code])
			if @invitation
				@user = User.find_by(invited_code: params[:code])
				if @user
					render json: {
						user: @user
					}, status: 200
					return
				else
					render json: {
						message: "can't find user info created from this code"
					}, status: 422
					return
				end
			else
				render json: {
					message: "Invalid invitation code."
				}, status: 422
				return
			end
		end

		private
		def invitation_params
			params.require(:invitation).permit(:label)
		end

		def set_invitation
			@invitation = current_user.invitations.find_by(id: params[:id])
			unless @invitation
				render json: {
					message: "You are not authorised to access."
				}, status: 422
			end
		end
	end
end