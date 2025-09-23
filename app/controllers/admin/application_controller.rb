# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
module Admin
  class ApplicationController < Administrate::ApplicationController
    include ApplicationHelper

    before_action :authenticate_admin

    def authenticate_admin
      redirect_to login_path unless logged_in? && current_user.admin?
    end

    helper_method :current_user, :logged_in?, :admin_user?

    def current_user
      @current_user ||= begin
        if session[:user_id]
          User.find_by(id: session[:user_id])
        elsif cookies.signed[:user_id] && cookies[:remember_token]
          user = User.find_by(id: cookies.signed[:user_id])
          if user&.valid_remember_token?(cookies[:remember_token])
            session[:user_id] = user.id
            user
          end
        end
      end
    end

    def logged_in?
      current_user.present?
    end

    def admin_user?
      logged_in? && current_user.admin?
    end

    # Override this value to specify the number of elements to display at a time
    # on index pages. Defaults to 20.
    def records_per_page
      params[:per_page] || 20
    end
  end
end
