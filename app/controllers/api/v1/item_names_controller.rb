module Api::V1
  class ItemNamesController < ApiController
    # This will return all item name
    # URl : v1/item_names
    # Method : GET
    def index
      render json: ItemName.all
    end
  end
end
