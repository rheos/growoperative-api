module Api::V1
  # Public intake form for "I want to start a new subnet" requests.
  #
  # - POST /v1/subnet_applications is open (no auth) so unregistered users
  #   in a new town can submit from the (auth)/apply-subnet screen.
  # - Index/update are superuser-only and live alongside SubnetsController.
  #
  # Approval is currently manual: a superuser reviews, then either creates
  # the Subnet via the existing tooling and PATCHes this row to
  # `approved` with `created_subnet_id`, or marks `rejected`. The model
  # does not auto-provision a Subnet — picking the seed user is a human
  # decision.
  class SubnetApplicationsController < ApiController
    skip_before_action :authenticate!, only: :create

    # POST /v1/subnet_applications
    def create
      application = SubnetApplication.new(application_params.merge(status: 'pending'))
      if application.save
        Rails.logger.info(
          "[subnet_application] new application id=#{application.id} " \
          "location=#{application.location.inspect} " \
          "community=#{application.community_name.inspect}"
        )
        render json: { id: application.id, status: application.status }, status: :created
      else
        render json: { errors: application.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # GET /v1/subnet_applications
    def index
      return forbidden! unless current_user&.is_superuser?
      apps = SubnetApplication.order(created_at: :desc)
      apps = apps.where(status: params[:status]) if params[:status].present?
      render json: { subnet_applications: apps.map { |a| serialize(a) } }, status: 200
    end

    # PATCH /v1/subnet_applications/:id
    def update
      return forbidden! unless current_user&.is_superuser?
      application = SubnetApplication.find(params[:id])

      attrs = {}
      if params.key?(:status)
        new_status = params[:status].to_s
        unless SubnetApplication::STATUSES.include?(new_status)
          return render json: { message: "Invalid status" }, status: 422
        end
        attrs[:status] = new_status
        if new_status != 'pending'
          attrs[:reviewed_by_user_id] = current_user.id
          attrs[:reviewed_at]         = Time.current
        end
      end
      attrs[:created_subnet_id] = params[:created_subnet_id] if params.key?(:created_subnet_id)

      if application.update(attrs)
        render json: serialize(application), status: 200
      else
        render json: { errors: application.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def application_params
      params.permit(:community_name, :location, :contact_name, :contact_email, :description)
    end

    def forbidden!
      render json: { message: 'Superuser access required' }, status: 403
    end

    def serialize(a)
      {
        id:                  a.id,
        community_name:      a.community_name,
        location:            a.location,
        contact_name:        a.contact_name,
        contact_email:       a.contact_email,
        description:         a.description,
        status:              a.status,
        reviewed_by_user_id: a.reviewed_by_user_id,
        reviewed_at:         a.reviewed_at&.iso8601,
        created_subnet_id:   a.created_subnet_id,
        created_at:          a.created_at.iso8601,
        updated_at:          a.updated_at.iso8601
      }
    end
  end
end
