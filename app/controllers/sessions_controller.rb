class SessionsController < ApplicationController
  def new
    redirect_to root_path if logged_in?
  end

  def create
    @user = User.authenticate(params[:login], params[:password])

    if @user
      log_in(@user)

      if params[:remember_me] == "1"
        remember(@user)
      end

      flash[:success] = "Welcome back, #{@user.display_name}!"
      redirect_to session[:return_to] || root_path
      session.delete(:return_to)
    else
      flash.now[:danger] = "Invalid email/username or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    if logged_in?
      forget(current_user)
      log_out
      flash[:notice] = "You have been logged out successfully."
    end
    redirect_to root_path
  end
end
