class AddUserPriceToInvitations < ActiveRecord::Migration[5.2]
  def change
    add_column :invitations, :user_price, :float
  end
end
