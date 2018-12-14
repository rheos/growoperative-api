module Api::V1
  class GradesController < ApiController
    before_action :authenticate_user!
    # This will return all item name
    # URl : v1/grades
    # Method : GET
    def index
      render json: Grade.all
    end
  end
end