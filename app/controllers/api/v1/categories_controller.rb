module Api::V1
  class CategoriesController < ApiController
    # This will return all item name
    # URl : v1/categories
    # Method : GET
    def index
      render json: Category.for_picker.map { |category|
        category.as_json(include: [:user_category_prices]).merge(
          default_unit: category.default_unit,
          allowed_units: category.allowed_units,
          kind: category.kind
        )
      }
    end
  end
end
