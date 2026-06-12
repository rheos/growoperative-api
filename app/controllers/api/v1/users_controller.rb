module Api::V1
	class UsersController < ApiController
		# before_action :authenticate_user!
		# Public handle endpoints (master plan §Handle Lookup Contract):
		# unauthenticated, rate-limited inside the actions. Skipping the
		# Authorization-header lookup keeps the lookup surface enumeration-
		# noisy rather than account-bearer-leakable.
		skip_before_action :authenticate!, only: [:by_handle, :handle_available]
		before_action :throttle_handle_lookup!, only: [:by_handle, :handle_available]
		before_action :is_admin_user, only: [:index, :get_invitation_limit, :set_invitation_limit, :chain_limit, :set_chain_limit]
		before_action :set_user, only: [:item_list, :get_invitation_limit, :set_invitation_limit, :chain_limit, :get_nickname, :set_nickname]
		# GET /v1/users
		def index
			users = if current_user.is_superuser?
				User.all
			else
				User.joins(:user_groups).where(user_groups: { group_label: 'demo' }).distinct
			end
			render json: users, include: [:user_groups], methods: [:invited_by_name]
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
			multi_use = ActiveModel::Type::Boolean.new.cast(params[:multi_use]) || false
			if multi_use || current_user.ramaining_invitation_limit > 0
				@invitation = current_user.invitations.new()
				custom_code = params[:invitation_code].presence || params[:custom_code].presence || params[:code].presence
				@invitation.multi_use = multi_use

				if custom_code.present?
					unless Invitation.easy_code?(custom_code)
						render json: {
							message: "Invitation code must be #{Invitation::EASY_CODE_MIN_LENGTH}-#{Invitation::EASY_CODE_MAX_LENGTH} letters or numbers"
						}, status: 422
						return
					end

					if Invitation.active_code_taken?(custom_code)
						render json: {
							message: "Invitation code is already active"
						}, status: 422
						return
					end

					@invitation.invitation_code = custom_code
				end

				# Pull a pronounceable code from auth.foaf.io's invitation
				# primitive (Job 23, CVCV-CVCV "mavo-leni") instead of the
				# legacy random alphanumeric. canonicalize_invitation_code
				# strips the hyphen and uppercases on save. On FOAF failure
				# we fall through to the local random-code generator so a
				# transient auth.foaf.io blip doesn't kill the inviter UX. Custom
				# and multi-use codes stay local because railsbackend owns their
				# active/inactive lifecycle.
				if @invitation.invitation_code.blank? && !multi_use && current_user.foaf_id.present?
					begin
						auth_status, auth_body = AuthFoafClient.create_invitation(
							inviter_foaf_id: current_user.foaf_id,
							target_app: 'growoperative'
						)
						if auth_status == 201 && auth_body['code'].present?
							@invitation.invitation_code = auth_body['code']
						else
							Rails.logger.warn("auth.foaf.io invite mint returned status=#{auth_status}; falling back to local random code")
						end
					rescue StandardError => e
						Rails.logger.warn("auth.foaf.io invite mint failed (#{e.class}: #{e.message}); falling back to local random code")
					end
				end

				if params[:user_type] != ''
					@invitation.user_type = params[:user_type]
				end
				if params[:user_price].present?
					@invitation.user_price = params[:user_price]
				end
				if params[:label].present?
					@invitation.label = params[:label].to_s.strip
				end
				@invitation.status = 0
				# Default the invitation's subnet to the inviter's primary. Nullable
				# during the backfill window — once Phase 3 runs, every existing user
				# has a primary membership and this will always be set.
				subnet = current_user.primary_subnet
				@invitation.subnet_id = subnet&.id
				# Subnet role policy: when the inviter's subnet has multi_role=false,
				# clamp the invitation's user_type to the first allowed role. Backend
				# is authoritative — downstream user_groups can never accrue roles
				# outside visible_roles for locked-role subnets, regardless of what
				# the client sends.
				if subnet
					flags = SiteConfig.for(subnet)
					unless flags[:multi_role]
						allowed = flags[:visible_roles].first
						@invitation.user_type = allowed if allowed.present?
					end
				end
				if @invitation.save
					render json: @invitation, status: 200
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
				# Guard against lowering the limit below the number of currently-
				# pending (not-yet-accepted) invitations — accepted ones don't
				# block further generation so they don't block limit changes.
				if @user.invitations.pending.count > params[:invite_limit].to_i
					render json: {
						message: "invitation limit can't be smaller than current pending invitations"
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
			# Skip relationships whose counterparty was deleted — a nil user/friend
			# would nil out below and crash the serialization + price loop, taking
			# out the whole contact book over one stale row (saw this with a leftover
			# relationship pointing at a deleted demo user).
			relationships = Relationship.where("user_id = :id OR friend_id = :id", id: current_user.id)
				.includes(:user, :friend)
				.select { |rel| rel.user.present? && rel.friend.present? }

			res = relationships.as_json(include: [{user: {include: [:user_groups], methods: [:avatar_url]} }, {friend: {include: [:user_groups], methods: [:avatar_url]} }, :user_relationship_prices])
			hydrate_contact_identity_avatars!(res)
			target_price = 0
			if params[:target_inventory_id].present? && Inventory.find(params[:target_inventory_id]).item.user_id != current_user.id
				res.each do |relation|
					friend_id = relation["user"]["id"] == current_user.id ? relation["friend"]["id"] : relation["user"]["id"]
					markup = helpers.get_relation_price(current_user.id, friend_id)
					relation["proposed_price"] = markup.value
					relation["proposed_price_type"] = markup.type
					relation["proposed_markup"] = markup.to_h
				end
			end
			default_markup = helpers.get_user_markup(current_user.id)
			render json: {
				items: res,
				default_markup: default_markup.value,
				default_markup_type: default_markup.type,
				default_markup_config: default_markup.to_h
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

			invitation = Invitation.find_by_code(params[:invited_code])
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
			
			if invitation.multi_use?
				unless invitation.active?
					render json: {
						message: "This invitation code is no longer active"
					}, status: 422
					return
				end
			else
				unless invitation.pending?
					render json: {
						message: "Invitation code is already used"
					}, status: 422
					return
				end
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
				# Status defaults to :pending if not set — the contract here is
				# an active acceptance, so set :accepted explicitly.
				relationship = Relationship.new(status: :accepted, action_user_id: current_user.id)

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

			if invitation.multi_use?
				invitation.invitation_redemptions.find_or_create_by!(user_id: current_user.id) do |r|
					r.redeemed_at = Time.current
				end
			else
				# update status
				invitation.update(status: :accepted, accepted_id: current_user.id)
			end

			# Record the connection in FOAF's contact_edges. Best-effort —
			# don't fail the local accept if the FOAF call errors (the local
			# Relationship + Invitation rows are still consistent). Phase 6
			# unifies this so railsbackend's invitations table itself moves
			# to auth.foaf.io and the contact_edge gets created server-side
			# during accept.
			begin
				if current_user.foaf_id.present? && invitation.user.foaf_id.present?
					AuthFoafClient.add_contact_edge(
						foaf_id_a: current_user.foaf_id,
						foaf_id_b: invitation.user.foaf_id
					)
				end
			rescue StandardError => e
				Rails.logger.warn("accept_invitation: FOAF contact_edge upsert failed (non-fatal): #{e.message}")
			end

			render json:{
				message: "Invitation accepted."
			}, status: 200
		end

		# Update password
		# URL : v1/users/update_password
		# Method : PATCH
		# Parameter : {"user": {"password": "hello124","password_confirmation": "hello124"}}
			def update_password
				# Proxy session-authorized password set/update to auth.foaf.io,
				# which owns the canonical hash. Returns the new RS256 token
				# and identity from the auth service so the client can refresh
				# its bearer and account-type state.
				new_password = params.dig(:user, :password).to_s
				confirm = params.dig(:user, :password_confirmation).to_s
				if new_password.blank? || new_password != confirm
					return render json: { message: 'Invalid password params' }, status: 422
				end

			match = request.headers['Authorization'].to_s.match(/\ABearer\s+(.+)\z/i)
				bearer = match && match[1]

				status, body = AuthFoafClient.change_password(
					new_password: new_password,
					bearer: bearer
				)
				if status == 200 && body['token']
					render json: UserSerializer.new(current_user).serializable_hash.merge(
						message: 'Password saved successfully.',
						token: body['token'],
						identity: body['identity'] || identity_payload(current_user)
					)
				elsif status == 422
					render json: { message: body['error'] || 'Invalid password' }, status: 422
				else
				Rails.logger.error("auth.foaf.io password change failed: status=#{status} body=#{body.inspect}")
				render json: { message: 'Password change failed' }, status: :bad_gateway
			end
		end

		# Upload or update user avatar
		# URL : v1/users/update_avatar
		# Method : PATCH
		# Parameter : multipart form with `avatar` file
		def update_avatar
			unless params[:avatar].present?
				render json: { error: "No avatar file provided" }, status: 422
				return
			end

			file = params[:avatar]
			# Read the bytes once for the auth.foaf.io mirror BEFORE CarrierWave
			# consumes the IO. Rewind defensively for the local save below.
			file.rewind if file.respond_to?(:rewind)
			bytes = file.respond_to?(:read) ? file.read : nil
			content_type = file.respond_to?(:content_type) ? file.content_type : 'application/octet-stream'
			file.rewind if file.respond_to?(:rewind)

			# Local save (CarrierWave → Growoperative S3, populates users.image).
			# Keeps railsbackend's contact_list and other consumers working
			# without an N+1 fetch into auth.foaf.io. (Phase 5+ dual-write —
			# see project_avatar_dual_write_then_per_app memory.)
			unless current_user.update(image: file)
				render json: { error: current_user.errors.full_messages.join(', ') }, status: 422
				return
			end

			# Mirror to auth.foaf.io so identities.avatar_url is populated and
			# the avatar shows up after re-login (the saga reads from
			# identity.avatar_url, not from the local users column).
			begin
				match = request.headers['Authorization'].to_s.match(/\ABearer\s+(.+)\z/i)
				bearer = match && match[1]
				if bytes && bearer
					auth_status, _auth_body = AuthFoafClient.upload_avatar(
						bytes: bytes,
						content_type: content_type,
						bearer: bearer
					)
					Rails.logger.info("auth.foaf.io avatar mirror status=#{auth_status}") if auth_status != 200
				end
			rescue StandardError => e
				# Non-fatal — local save already succeeded. Avatar will appear
				# on next refresh in-session but not after re-login until the
				# next successful upload mirrors to auth.foaf.io.
				Rails.logger.warn("auth.foaf.io avatar mirror failed: #{e.class}: #{e.message}")
			end

			render json: {
				message: "Avatar updated successfully.",
				avatar_url: current_user.avatar_url
			}
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

	# GET /v1/users/profile
	# Self-profile read used by FoafAuthClient. Returns identity + the
	# legacy data.attributes envelope. Job 43: token is no longer reissued
	# here (railsbackend stopped minting). Client uses its existing bearer;
	# refresh via re-login when expiry approaches.
	def profile
		render json: UserSerializer.new(current_user).serializable_hash.merge(
			identity: identity_payload(current_user),
		), status: 200
	end

	# GET /v1/profile
	# App-owned profile only. Identity fields live in auth.foaf.io and the
	# protocol identity payload; this endpoint returns Growoperative-local
	# fields keyed by foaf_id.
	def app_profile
		render json: app_profile_payload(current_user), status: 200
	end

	# PATCH /v1/users/profile
	# Identity-shaped self-update. Proxies to auth.foaf.io, which owns the
	# canonical identity (mirrors update_password). Accepts first_name,
	# last_name, display_name, pending_email, and email. Auth handles the email
	# semantics: a verified-email change flows through `pending_email` + a
	# verification step; `email: ''` clears it (gated on a recovery phrase); a
	# direct `email` write is dropped. The app reads email/email_verified_at/
	# pending_email from auth's identity block. We still mirror the app-owned
	# name fields onto the local users row so contact_list / serializers stay
	# consistent without a round-trip to auth.
	def update_profile
		patch = profile_update_params

		match = request.headers['Authorization'].to_s.match(/\ABearer\s+(.+)\z/i)
		bearer = match && match[1]

		status, body = AuthFoafClient.update_profile(patch: patch.to_h, bearer: bearer)

		if status == 200
			local_mirror = patch.slice(:first_name, :last_name, :display_name)
			current_user.update(local_mirror) if local_mirror.present?
			render json: UserSerializer.new(current_user).serializable_hash.merge(
				identity: body['identity'] || identity_payload(current_user),
			), status: 200
		elsif status == 422
			render json: { errors: [body['error']].compact, code: body['code'] }.compact, status: 422
		else
			Rails.logger.error("auth.foaf.io profile update failed: status=#{status} body=#{body.inspect}")
			render json: { message: 'Profile update failed' }, status: :bad_gateway
		end
	end

	# GET /v1/users/by_handle/:handle
	# Public handle lookup (master plan §Handle Lookup Contract). Returns
	# only the four documented fields. 404 for missing/deleted users —
	# never reveal email, role, subnet, admin flags, or invite limits.
	def by_handle
		handle = params[:handle].to_s.downcase
		user = User.find_by(user_name: handle)
		if user
			render json: {
				foaf_id: user.foaf_id,
				user_name: user.user_name,
				display_name: user.display_name,
				avatar_url: user.avatar_url,
			}, status: 200
		else
			render json: { error: 'not_found' }, status: 404
		end
	end

	# GET /v1/users/handle_available?handle=...
	# Active-identity check + format check. Phase-3 (Job 17) layers
	# reserved-handle, cooldown, and reserved-word checks on top.
	def handle_available
		handle = params[:handle].to_s.downcase
		if !valid_handle_format?(handle)
			render json: { available: false, reason: 'invalid_format' }, status: 200
			return
		end
		taken = User.where('LOWER(user_name) = ?', handle).exists?
		render json: { available: !taken }, status: 200
	end

		private

		# Phase-2 interim rate limit for the public handle endpoints.
		# Per-IP sliding window via Rails.cache.increment; full
		# rack-attack throttles land with auth.foaf.io (Job 26). Limit
		# is generous so signup UX (live availability checks while
		# typing) doesn't trip it; tighten once we have observability.
		HANDLE_LOOKUP_LIMIT = 60   # requests
		HANDLE_LOOKUP_WINDOW = 60  # seconds

		def throttle_handle_lookup!
			ip = request.remote_ip.to_s
			# Bucket by 60-second wall-clock window so the cache key TTL
			# matches the window — increment is atomic, key auto-expires.
			bucket = (Time.now.to_i / HANDLE_LOOKUP_WINDOW)
			key = "rate:handle_lookup:#{ip}:#{bucket}"
			count = Rails.cache.increment(key, 1, expires_in: HANDLE_LOOKUP_WINDOW * 2)
			# Some cache stores return nil on first increment — initialize.
			if count.nil?
				Rails.cache.write(key, 1, expires_in: HANDLE_LOOKUP_WINDOW * 2)
				count = 1
			end
			if count > HANDLE_LOOKUP_LIMIT
				response.set_header('Retry-After', HANDLE_LOOKUP_WINDOW.to_s)
				render json: { error: 'rate_limited' }, status: 429
			end
		end

		# Mirrors User.normalize_user_name expectations: lowercase only,
		# 2–32 chars, alphanumerics + `_` + `.` + `-`. Keep this loose
		# enough to accept the existing dataset (no migration required)
		# but tight enough to reject obvious junk in handle_available.
		HANDLE_FORMAT = /\A[a-z0-9][a-z0-9_.\-]{1,31}\z/

		def valid_handle_format?(handle)
			HANDLE_FORMAT.match?(handle)
		end

		def hydrate_contact_identity_avatars!(relationships)
			cache = {}
			relationships.each do |relationship|
				%w[user friend].each do |side|
					user_payload = relationship[side]
					next unless user_payload.is_a?(Hash)
					next if user_payload['avatar_url'].present?

					handle = user_payload['user_name'].to_s
					next if handle.blank?

					user_payload['avatar_url'] = identity_avatar_for_handle(handle, cache)
				end
			end
		end

		def identity_avatar_for_handle(handle, cache)
			cache.fetch(handle) do
				cache[handle] = begin
					status, body = AuthFoafClient.identity_by_handle(handle: handle)
					status == 200 && body.is_a?(Hash) ? body['avatar_url'] : nil
				rescue StandardError => e
					Rails.logger.warn("auth.foaf.io identity avatar lookup failed for #{handle}: #{e.class}: #{e.message}")
					nil
				end
			end
		end

		def profile_update_params
			# Tolerate both nested (`{user: {...}}`) and flat shapes — same
			# bridge-window contract as Job 06's signup body. Whitelist is
			# strictly FoafIdentity fields; profile-shaped fields like
			# `invite_limit` and `is_admin` go through their own routes.
			source = params[:user].present? ? params[:user] : params
			source = ActionController::Parameters.new(source) unless source.is_a?(ActionController::Parameters)
			source.permit(:first_name, :last_name, :display_name, :email, :pending_email)
		end


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
