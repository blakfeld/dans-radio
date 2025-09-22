# Spotify Console Helper Methods
# These are automatically available in Rails console

if defined?(Rails::Console)

  # Helper method to get Spotify user with workaround
  def spotify_user
    username = Rails.application.config.spotify[:user_name]
    spotify_user = SpotifyUser.find_by(username: username)

    if spotify_user
      # This is the workaround - recreate from stored credentials
      spotify_user.to_rspotify_user
    else
      puts "No SpotifyUser found for '#{username}'. Authenticate first at https://dansradio.dev/"
      nil
    end
  end

  # Shorthand alias
  def suser
    spotify_user
  end

  # Quick test method
  def test_spotify
    user = spotify_user
    if user
      puts "Connected as: #{user.id}"
      puts "Playlists: #{user.playlists(limit: 3).map(&:name).join(', ')}"
      true
    else
      false
    end
  end

  puts "=" * 60
  puts "Spotify Console Helpers Loaded!"
  puts "=" * 60
  puts "Available methods:"
  puts "  spotify_user or suser - Get Spotify user (with workaround)"
  puts "  test_spotify         - Quick connection test"
  puts ""
  puts "Example usage:"
  puts "  user = spotify_user"
  puts "  user.playlists"
  puts "=" * 60
end
