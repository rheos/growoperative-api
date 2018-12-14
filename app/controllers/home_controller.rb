class HomeController < ApplicationController
  before_action :authenticate_user!
  def authenticate_user!
    if user_signed_in?
      super
    else
      render template: "login.html.erb"
      ## if you want render 404 page
      ## render :file => File.join(Rails.root, 'public/404'), :formats => [:html], :status => 404, :layout => false
    end
  end
  def dashboard
  	render template: "dashboard.html.erb"
  end
  def invites
  	render template: "invites.html.erb"
  end
  def myAccount
  	render template: "myAccount.html.erb"
  end
  def contact
    render template: "contact.html.erb"
  end
  def admin
    render template: "admin.html.erb"
  end
  def viewUser
    @invitationCode = params[:id]
    render template: "viewUser.html.erb"
  end
end