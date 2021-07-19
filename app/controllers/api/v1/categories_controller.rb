module Api::V1
  class CategoriesController < ApiController
    # This will return all item name
    # URl : v1/categories
    # Method : GET
    def index
      render json: Category.all, include: [:user_category_prices]
    end
  end
end
