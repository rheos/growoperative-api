module Api::V1
	class UsersController < ApiController
		# before_action :authenticate_user!
		before_action :is_admin_user, only: [:index, :get_invitation_limit, :set_invitation_limit, :chain_limit, :set_chain_limit]
		before_action :set_user, only: [:item_list, :get_invitation_limit, :set_invitation_limit, :chain_limit, :get_nickname, :set_nickname]
		# GET /v1/users
		def index
			render json: User.all, include: [:user_groups]
		end

		# GET /v1/users/{id}
		def show
			render json: User.find(params[:id])
		end

		def update_relation
			relation = Relationship.find_by(id: params[:id])

			render json: { message: "Relation not found"}, status: 404 if (!relation || (relation.user_id != current_user.id && relation.friend_id != current_user.id))

			if relation.user_id == current_user.id
				relation.update(actions_state: params[:actions_state])
			else
				relation.update(friend_actions_state: params[:actions_state])
			end

			render json: relation, status: 200
		end


		# url : /v1/current_user_types
		# method : GET
		def current_user_types
			user_groups = current_user.user_groups
			render json: user_groups
		end
		#Get
		#URL : v1/users/generate_invitation?user_type=consumer
		def generate_invitation
			if current_user.ramaining_invitation_limit > 0
				@invitation = current_user.invitations.new()
				# @invitation.label = current_user.user_name
				if params[:user_type] != ''
					@invitation.user_type = params[:user_type]
				end
				if params[:user_price].present?
					@invitation.user_price = params[:user_price]
				end
				@invitation.status = 0
				if @invitation.save!
				render json: {
					invitation_code: @invitation.invitation_code
				}, status: 200
				else
					render json: @invitation.errors, status: 422
				end
			else
				render json: {
					message: "Invitation limit over"
				}, status: 422
			end
		end

		# Get Invitation Limit
		# url : v1/users/:id_of_user/get_invitation_limit
		def get_invitation_limit
			render json: {
				data: {
					invite_limit: @user.invite_limit,
					invited_count: @user.invitations_count
				}
			}
		end

		# This method will return Nickname of User
		# URL : /v1/users/:id/get_nickname
		def get_nickname
			render json: {
				data: {
					nick_name: @user.nickname
				}
			}, status: 200
		end

		# Update Nick name
		# URL : v1/users/:id/set_nickname
		# Method : PATCH
		# Parameter : {"user": {"nickname": "Test"}}
		def set_nickname
			if @user.update(user_params)
				render json: {
					message: "Nickname update successfully."
				}
			else
				render :json=> @user.errors, :status=>422
			end
		end

		# set invitation limit
		# url : v1/users/:id_of_user/set_invitation_limit
		# parameter : { "invite_limit": 3 }
		def set_invitation_limit
			if params[:invite_limit].to_i == 0
				render json: {
						message: "Please enter number only"
					}, status: 401
					return
			end
			if params[:invite_limit].present? && params[:invite_limit] != ""
				if @user.invitations_count > params[:invite_limit].to_i
					render json: {
						message: "invitation limit can't be smaller than current inviations count"
					}, status: 401
					return
				end
				if @user.update(invite_limit: params[:invite_limit].to_i)
					render json: {
						message: "Invite limit changed."
					}, status: 200
				else
					render json: {
					message: "Please try again."
				}, status: 401
				end
			else
				render json: {
					message: "Invite limit can't be blanck."
				}, status: 401
			end
		end

		# contact list
		# url : v1/users/contact_list?:target_inventory_id
		def contact_list
			relationships = Relationship.where("user_id = #{current_user.id} OR friend_id = #{current_user.id}")

			res = relationships.as_json(include: [{user: {include: [:user_groups]} }, {friend: {include: [:user_groups]} }, :user_relationship_prices])
			target_price = 0
			if params[:target_inventory_id].present? && Inventory.find(params[:target_inventory_id]).item.user_id != current_user.id
				res.each do |relation|
					friend_id = relation["user"]["id"] == current_user.id ? relation["friend"]["id"] : relation["user"]["id"]
					relation["proposed_price"] = helpers.get_relation_price(current_user.id, friend_id)
				end
			end
			render json: {
				items: res, default_markup: helpers.get_user_markup(current_user.id)
			}, status: 200
		end

		# Accept invitation will build relationship
		# url : v1/users/accept_invition
		# parameter : invited_code
		# method : POST
		def accept_invitation
			unless params[:invited_code].present?
				render json: {
					message: "Invitation code can't be blank."
				}, status: 422
				return
			end

			invitation = Invitation.find_by(invitation_code: params[:invited_code])
			if invitation.nil?
				render json: {
					message: "Invalid invitation code."
				}
				return
			end
			
			if invitation.user_id == current_user.id
				render json: {
					message: "You can not accept your own invitation."
				}, status: 422
				return
			end
			
			unless invitation.pending?
				render json: {
					message: "Invitation code is already used"
				}, status: 422
				return
			end

			# Prevent non-demo users from accepting demo invitations (and vice versa)
			if invitation.user.demo? != current_user.demo?
				render json: {
					message: "This invitation is not available"
				}, status: 422
				return
			end
			
			# create a relationship if not exists
			relationship = Relationship.where("(user_id = #{invitation.user.id} AND friend_id = #{current_user.id}) 
																						OR (user_id = #{current_user.id} AND friend_id = #{invitation.user.id})")
			if relationship.size == 0
				relationship = Relationship.new

				if current_user.id < invitation.user_id
					relationship.user_id = current_user.id
					relationship.friend_id = invitation.user_id
					relationship.user_label = invitation.note_label
					relationship.friend_label = invitation.label
				else
					relationship.user_id = invitation.user_id
					relationship.friend_id = current_user.id
					relationship.user_label = invitation.label
					relationship.friend_label = invitation.note_label
				end

				relationship.save
			end

			# add the invitiation group if the user doesn't have it
			current_user.user_groups.find_or_create_by(group_label: invitation.user_type)

			# update status
			invitation.update(status: :accepted, accepted_id: current_user.id)

			render json:{
				message: "Invitation accepted."
			}, status: 200
		end

		# Update password
		# URL : v1/users/update_password
		# Method : PATCH
		# Parameter : {"user": {"password": "hello124","password_confirmation": "hello124"}}
		def update_password
			@user = current_user
			if @user.valid_password?(params[:user][:current_password])
				if @user.update(user_params)
					bypass_sign_in current_user
					render json: {
						message: "Password changed successfully."
					}
				else
					render :json=> @user.errors, :status=>422
				end
			else
				render json: {
					message: "current password is not valid"
				}, status: 422
			end
		end

		# This api will update userlabel
		# URL : v1/users/edit_contact_label
		# Method : PATCH
		# Parameter : { "first_id": 2, "second_id": 4, "new_label": "Test" }
		def edit_contact_label
		if (params[:first_id] != "" && params[:second_id] != "" && params[:new_label] != "")
			first_id = params[:first_id]
			second_id = params[:second_id]
			relationship = Relationship.find_by("user_id IN (?) AND friend_id IN (?)",[second_id, first_id],[second_id, first_id] )
			if relationship
				if first_id.to_i > second_id.to_i
					relationship.friend_label = params[:new_label]
				else
				relationship.user_label = params[:new_label]
				end
			if relationship.save
				render json: {
				message: "Update label successfully"
				}, status: 200
			else
				render :json=> relationship.errors, status:422
			end
			else
			render json: {
				message: "Invalid value entered."
			}, status: 422
			end
		else
			render json: {
				message: "Please submit proper value"
			},status: 422
		end
    end

    # This api will return contact label
    # URL : v1/users/get_contact_label
    # method : POST
    # parameter : { "first_id": 2, "second_id": 1 }
    def get_contact_label
    	ids = [params[:first_id], params[:second_id]]
    	@relationships = Relationship.where("user_id IN (?) AND friend_id IN (?)", ids, ids)
    	if @relationships
    		render json: {
    			data: @relationships
    		},status: 200
    	else
    		render json: {
    			message: "There is no record found"
    		}, status: 422
    	end
    end
    # This api will return Items of user
    # URL : /v1/users/:id/item_list
    def item_list
    	render json: @user.items, status: 200
	end
	
	# This api will rdestroy relation between 2 users
	# URL : /v1/users/destroy_relationship
	# method : POST
    # parameter : { "id": 2 }
	def destroy_relationship
		relation = Relationship.where("id = (?) AND (user_id = (?) OR friend_id = (?))", params[:id], current_user.id, current_user.id).first
		render json: { message: 'Relation was not found'}, status: 404 unless relation
		
		relation.destroy!

		render json: { message: 'Success' }, status: 200
	end

	def category_sizes
		render json: current_user.category_sizes.map {|s| s.as_json}, status: 200
	end

	def create_category_size
		if params[:size_id]
			size = CategorySize.find(params[:size_id])
			size.update(category_size_params)
		else
			size = current_user.category_sizes.create(category_size_params)
		end

		if size
			render json: size.as_json, status: 200
		else
			render json: { message: 'Unable to create category size!' }, status: 422
		end
	end

	def destroy_category_size
		size = CategorySize.find_by(id: params[:id])
		if size && size.destroy
			render json: { message: 'Category size was succesfully removed!' }, status: 200
		else
			render json: { message: 'Unable to dind or remove category size!' }, status: 422
		end
	end

		private
		def set_user
			@user = User.find_by(id: params[:id])
			unless @user
				render json: {message: "User not found" }, status: 200
			end
		end

		def is_admin_user
			unless current_user.is_admin?
				render json: {message: "You are not allowed" }, status: 200
			end
		end

		def user_params
			# NOTE: Using `strong_parameters` gem
			params.require(:user).permit(:password, :password_confirmation, :nickname, :current_password)
		end

		def category_size_params
			params.permit(:quantity, :category_id, :item_unit_id, :price)
		end

	end
end
