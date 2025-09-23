module Admin
  class UsersController < Admin::ApplicationController
    helper_method :current_user  # Make current_user available to views
    # Custom actions for user management
    def unlock
      user = User.find(params[:id])
      if user.locked?
        user.unlock!
        flash[:notice] = "User #{user.display_name} has been unlocked."
      else
        flash[:alert] = "User #{user.display_name} was not locked."
      end
      redirect_to admin_users_path
    end

    def toggle_admin
      user = User.find(params[:id])

      if user == current_user
        flash[:alert] = "You cannot change your own admin status."
      elsif !user.admin? || User.admins.count > 1
        user.update(admin: !user.admin?)
        status = user.admin? ? "granted admin privileges" : "removed from admin role"
        flash[:notice] = "User #{user.display_name} was #{status}."
      else
        flash[:alert] = "Cannot remove admin privileges from the last admin user."
      end

      redirect_to admin_users_path
    end

    # Override resource_params to handle password fields properly
    def resource_params
      params.require(resource_class.model_name.param_key).
        permit(dashboard.permitted_attributes(action_name)).
        then do |p|
          # Remove password fields if they're blank
          if p[:password].blank? && p[:password_confirmation].blank?
            p.except(:password, :password_confirmation)
          else
            p
          end
        end
    end

    # Override to prevent users from deleting themselves
    def destroy
      user = requested_resource

      if user == current_user
        flash[:alert] = "You cannot delete your own account."
        redirect_to admin_users_path
      elsif user.admin? && User.admins.count == 1
        flash[:alert] = "Cannot delete the last admin user."
        redirect_to admin_users_path
      else
        super
      end
    end
  end
end
