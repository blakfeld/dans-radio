require "rspotify/oauth"

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :spotify,
           Rails.application.credentials.spotify[:client_id],
           Rails.application.credentials.spotify[:client_secret],
           scope: "user-read-email user-read-private user-library-read user-library-modify user-top-read user-read-recently-played user-follow-read user-follow-modify playlist-read-private playlist-read-collaborative playlist-modify-public playlist-modify-private user-modify-playback-state user-read-playback-state",
           callback_path: "/auth/spotify/callback"
end

OmniAuth.config.allowed_request_methods = %i[get post]
# This is important for development with self-signed certificates
OmniAuth.config.full_host = lambda do |env|
  scheme = env["rack.url_scheme"]
  host = env["HTTP_HOST"] || env["SERVER_NAME"]
  port = env["SERVER_PORT"]

  # Build the full URL with the current scheme and host
  "#{scheme}://#{host}"
end
