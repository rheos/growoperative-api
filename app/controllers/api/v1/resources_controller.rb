module Api::V1
  class ResourcesController < ApiController
    # before_action :authenticate_user_by_cookie

    def index
      
      #binding.pry
      send_file (Rails.root.to_s + '/private/' + params[:file_path] + '.' + params[:format])
    end

    private
    def authenticate_user_by_cookie
      request.headers[:Authorization] = cookies[:token] if !request.headers[:Authorization]
      authenticate_user!
    end
  end
end
