class Invitation < ApplicationRecord
  # It handle status value as enum
  enum status: [ :pending, :accepted ]
  enum user_type: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin]
  belongs_to :user

  # Callbacks
  before_create :generate_invitation_code
  after_create :set_user_type

  # This method will geneate uniq invitation code of 8 digit.
  # It will contation Number & character.
  def generate_invitation_code
    size = 8
    charset = ([*('A'..'Z'),*('0'..'9')]-["O"]).sample(size).join
     begin
      random_string = charset
      self.invitation_code = random_string
    end while self.class.exists?(:invitation_code => random_string)
  end


  def set_user_type
    if self.user_type == ''
      user_type = self.user.user_groups.pluck(:group_label)
      case user_type
      when user_type.include?("admin")
        self.update user_type: "producer"
      when user_type.include?("producer")
        self.update user_type: "producer"
      when user_type.include?("wholesaler")
        self.update user_type: "producer"
      when user_type.include?("broker")
        self.update user_type: "broker"
      when user_type.include?("retailer")
        self.update user_type: "consumer"
      when user_type.include?("consumer")
        self.update user_type: "consumer"
      end
    end
  end
end
