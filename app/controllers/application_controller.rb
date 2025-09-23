class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Security measures
  protect_from_forgery with: :exception

  # Authentication helpers
  before_action :set_current_user

  helper_method :current_user, :logged_in?, :admin_user?

  private

  def current_user
    @current_user ||= begin
      if session[:user_id]
        User.find_by(id: session[:user_id])
      elsif cookies.signed[:user_id] && cookies[:remember_token]
        user = User.find_by(id: cookies.signed[:user_id])
        if user&.valid_remember_token?(cookies[:remember_token])
          log_in(user)
          user
        end
      end
    end
  end

  def set_current_user
    current_user
  end

  def logged_in?
    current_user.present?
  end

  def admin_user?
    logged_in? && current_user.admin?
  end

  def log_in(user)
    session[:user_id] = user.id
    @current_user = user
  end

  def log_out
    forget(current_user)
    session.delete(:user_id)
    @current_user = nil
  end

  def remember(user)
    token = user.generate_remember_token!
    cookies.permanent.signed[:user_id] = user.id
    cookies.permanent[:remember_token] = token
  end

  def forget(user)
    user&.clear_remember_token!
    cookies.delete(:user_id)
    cookies.delete(:remember_token)
  end

  def require_login
    unless logged_in?
      session[:return_to] = request.original_url
      flash[:alert] = "You must be logged in to access this page."
      redirect_to login_path
    end
  end

  def require_admin
    unless admin_user?
      flash[:danger] = "You must be an admin to access this page."
      redirect_to root_path
    end
  end

  def redirect_if_logged_in
    redirect_to root_path if logged_in?
  end
end
