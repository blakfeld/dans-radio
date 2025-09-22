module Admin
  class BaseController < ApplicationController
    layout "admin"

    # Add authentication here if needed
    # before_action :authenticate_admin!

    private

    def authenticate_admin!
      # Implement your admin authentication logic here
      # For now, we'll allow all access
      # In production, you should add proper authentication
    end
  end
end
