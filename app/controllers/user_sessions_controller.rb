class UserSessionsController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]

  skip_before_filter :deny_access_to_all
  access_control do
    actions :create do
      allow anonymous
    end
    action :destroy do
      allow logged_in
    end
  end

  def create
    @user_session = UserSession.new(params[:user_session])
    if @user_session.save
      flash[:notice] = "Login successful!"
      redirect_back_or_default root_url
    else
      flash[:error] = @user_session.errors.full_messages.to_sentence
      redirect_back_or_default root_url
    end
  end
  
  def destroy
    current_user_session.destroy
    flash[:notice] = "Logout successful!"
    redirect_to root_url
  end 


end
