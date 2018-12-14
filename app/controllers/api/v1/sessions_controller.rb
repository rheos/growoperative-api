class Api::V1::SessionsController < Devise::SessionsController
  prepend_before_action :require_no_authentication, only: [:new, :create]
  # prepend_before_action :allow_params_authentication!, only: :create
  prepend_before_action :verify_signed_out_user, only: :destroy
  prepend_before_action(only: [:create, :destroy]) { request.env["devise.skip_timeout"] = true }
  before_action :ensure_params_exist, only: [:create]
  respond_to :json
  
  def create
    resource = User.find_for_database_authentication(:user_name=>params[:user_name])
    return invalid_login_attempt unless resource

    if resource.valid_password?(params[:password])
      sign_in("user", resource)
      # respond_with resource
      render json: { success: true,
        message: "Log in successfully Use token provided in header to access other urls.",
        data: resource }
      return
    end
    invalid_login_attempt
  end

  def destroy
    sign_out(resource_name)
  end

  protected
  def ensure_params_exist
    return unless params[:user_name].blank?
    render :json=>{ success:false, message: "Username can't be blank"}, status:422
  end

  def invalid_login_attempt
    warden.custom_failure!
    render :json=> {:success=>false, :message=>"Username or password are invalid"}, :status=>401
  end


  # def destroy
  #   sign_out(resource_name)
  # end

  private

    def respond_with(resource, _opts = {})
      case action_name
      when 'create'
        content = "Log in successfully Use token provided in header to access other urls."
      else
        content = resource
      end
      render json: content.to_json
    end

    def respond_to_on_destroy
      render json: "LogOut successfully."
    end
end