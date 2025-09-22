# Spotify Console Helper
# This script helps you test Spotify functionality in Rails console
# without running into the @@users_credentials issue
#
# Usage in Rails console:
# 1. Load this helper: load 'lib/spotify_console_helper.rb'
# 2. Use the provided methods to interact with Spotify

module SpotifyConsoleHelper
  extend self

  # Authenticate a user manually (useful for initial setup)
  def authenticate_user_manually
    puts "=" * 60
    puts "Manual Spotify Authentication"
    puts "=" * 60
    puts "\nTo authenticate, you need to:"
    puts "1. Start your Rails server: rails server"
    puts "2. Visit: http://localhost:3000/auth/spotify"
    puts "3. Log in with Spotify and authorize the app"
    puts "4. Once redirected back, check the database:"
    puts "   SpotifyUser.last"
    puts "=" * 60
  end

  # Create a mock user for testing (requires valid OAuth tokens)
  def create_test_user(username:, token:, refresh_token:, expires_at: 1.hour.from_now)
    spotify_user = SpotifyUser.find_or_initialize_by(username: username)
    spotify_user.update!(
      token: token,
      refresh_token: refresh_token,
      expires_at: expires_at,
      email: "#{username}@example.com"
    )

    puts "Created/Updated SpotifyUser: #{spotify_user.username}"
    spotify_user
  end

  # Get the current Spotify user with workaround applied
  def get_spotify_user(username = nil)
    username ||= Rails.application.config.spotify[:user_name]

    spotify_user = SpotifyUser.find_by(username: username)
    if spotify_user
      puts "Found SpotifyUser: #{spotify_user.username}"

      # This is the workaround - recreate the RSpotify::User from stored credentials
      rspotify_user = spotify_user.to_rspotify_user
      puts "Created RSpotify::User from stored credentials"

      rspotify_user
    else
      puts "No SpotifyUser found for '#{username}'"
      puts "Please authenticate first using authenticate_user_manually()"
      nil
    end
  end

  # Test playlist operations
  def test_playlist_operations
    user = get_spotify_user
    return unless user

    begin
      playlists = user.playlists(limit: 5)
      puts "\nFound #{playlists.size} playlists:"
      playlists.each do |playlist|
        puts "  - #{playlist.name} (#{playlist.tracks.size} tracks)"
      end

      playlists.first
    rescue => e
      puts "Error: #{e.message}"
      puts "You may need to re-authenticate"
      nil
    end
  end

  # Test search operations (doesn't require user auth)
  def test_search(query = "The Beatles")
    begin
      artists = RSpotify::Artist.search(query, limit: 3)
      puts "\nSearch results for '#{query}':"
      artists.each do |artist|
        puts "  - #{artist.name} (#{artist.popularity} popularity)"
      end

      artists.first
    rescue => e
      puts "Error: #{e.message}"
      nil
    end
  end

  # Test service classes with workaround
  def test_service_classes
    # Test GetPlaylist service
    playlist_service = Spotify::GetPlaylist.new(name: "Discover Weekly", id: nil)
    begin
      playlist = playlist_service.call
      if playlist
        puts "Successfully retrieved playlist: #{playlist.name}"
      else
        puts "Could not find playlist"
      end
    rescue => e
      puts "GetPlaylist error: #{e.message}"
    end

    # Test FindArtist service
    artist_service = Spotify::FindArtist.new(name: "The Beatles")
    begin
      artists = artist_service.call
      puts "\nFound #{artists.size} artists"
    rescue => e
      puts "FindArtist error: #{e.message}"
    end
  end

  # Helper to debug current state
  def debug_state
    puts "\n" + "=" * 60
    puts "Current Spotify Configuration:"
    puts "  User Name: #{Rails.application.config.spotify[:user_name]}"

    puts "\nSpotifyUser Records:"
    SpotifyUser.all.each do |user|
      puts "  - #{user.username} (token expires: #{user.expires_at || 'never'})"
    end

    puts "\nTrying to access RSpotify class variable:"
    begin
      # This will fail if the class variable is not initialized
      RSpotify::User.class_eval { @@users_credentials }
      puts "  @@users_credentials is initialized"
    rescue NameError
      puts "  @@users_credentials is NOT initialized (this is the issue)"
    end

    puts "=" * 60
  end

  # Quick start guide
  def help
    puts <<~HELP

      ========================================
      Spotify Console Helper Commands:
      ========================================

      authenticate_user_manually    - Instructions for OAuth authentication
      create_test_user(...)        - Create a test user with tokens
      get_spotify_user             - Get the current Spotify user (with workaround)
      test_playlist_operations     - Test playlist API calls
      test_search                  - Test search API (no auth needed)
      test_service_classes         - Test your service classes
      debug_state                  - Show current configuration and state
      help                         - Show this help message

      Quick Start:
      1. Run: authenticate_user_manually
      2. Follow the instructions to authenticate via browser
      3. Run: test_playlist_operations

      ========================================

    HELP
  end
end

# Make methods available at top level in console
include SpotifyConsoleHelper

puts "Spotify Console Helper loaded! Type 'help' for available commands."
