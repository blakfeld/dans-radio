class AuthController < ApplicationController
  def login
    # This action displays a login page with a link to /auth/spotify
    # The actual OAuth is handled by OmniAuth middleware
  end

  def callback
    # This is where Spotify redirects after authentication
    # The auth hash is available in request.env['omniauth.auth']
    auth = request.env["omniauth.auth"]

    if auth
      # Save the user credentials to database
      @spotify_user = SpotifyUser.from_omniauth(auth)

      # Also create the RSpotify user (this sets the class variable)
      # This is optional but helps with immediate usage
      RSpotify::User.new(auth.to_hash)

      flash[:notice] = "Successfully authenticated with Spotify as #{@spotify_user.username}"
      # Redirect to setup page if coming from there, otherwise root
      redirect_to session[:return_to] || setup_index_path
    else
      flash[:alert] = "Authentication failed"
      redirect_to session[:return_to] || root_path
    end
  rescue => e
    Rails.logger.error "Spotify OAuth error: #{e.message}"
    flash[:alert] = "Authentication error: #{e.message}"
    redirect_to session[:return_to] || root_path
  ensure
    session.delete(:return_to)
  end
end
