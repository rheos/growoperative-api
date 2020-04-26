class Api::V1::ItemUnitsController < Api::V1::ApiController
	before_action :authenticate_user!, only: [:index]
  
  def index
    render json: ItemUnit.all, status: 200
  end

end