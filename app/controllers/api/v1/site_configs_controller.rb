class Api::V1::SiteConfigsController < Api::V1::ApiController
  def show
    subnet = resolve_subnet
    return render json: { message: 'Subnet not found' }, status: 404 if subnet.nil? && params[:subnet_id].present?

    unless subnet.nil? || current_user_member_of?(subnet)
      return render json: { message: 'Not a member of this subnet' }, status: 403
    end

    render json: {
      subnet_id: subnet&.id,
      subnet_name: subnet&.name,
      config: SiteConfig.for(subnet)
    }
  end

  private

  def resolve_subnet
    if params[:subnet_id].present?
      Subnet.find_by(id: params[:subnet_id])
    else
      current_user.subnet_memberships.primary.first&.subnet ||
        current_user.subnet_memberships.first&.subnet
    end
  end

  def current_user_member_of?(subnet)
    current_user.subnet_memberships.exists?(subnet_id: subnet.id)
  end
end
