class Inventory < ApplicationRecord
  mount_uploader :image, GeneralImagesUploader
end
  