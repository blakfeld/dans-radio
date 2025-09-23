ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/reporters"
require "webmock/minitest"
require "vcr"
require "ostruct"
require "mocha/minitest"

# SimpleCov for test coverage
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter "/test/"
    add_filter "/config/"
    add_filter "/vendor/"
    add_group "Controllers", "app/controllers"
    add_group "Models", "app/models"
    add_group "Services", "app/services"
    add_group "Jobs", "app/jobs"
    add_group "Helpers", "app/helpers"
  end
end

# Better test output formatting
Minitest::Reporters.use! [ Minitest::Reporters::DefaultReporter.new ]

# Configure VCR for recording HTTP interactions
VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.ignore_localhost = true
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: [ :method, :uri, :body ]
  }

  # Filter out sensitive data
  config.filter_sensitive_data("<SPOTIFY_CLIENT_ID>") { ENV["SPOTIFY_CLIENT_ID"] }
  config.filter_sensitive_data("<SPOTIFY_CLIENT_SECRET>") { ENV["SPOTIFY_CLIENT_SECRET"] }
  config.filter_sensitive_data("<SPOTIFY_ACCESS_TOKEN>") do |interaction|
    interaction.request.headers["Authorization"]&.first
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Helper to create mock Spotify API objects using OpenStruct
    def mock_spotify_track(attrs = {})
      OpenStruct.new({
        id: attrs[:id] || "spotify_track_123",
        name: attrs[:name] || "Test Song",
        duration_ms: attrs[:duration_ms] || 180000,
        explicit: attrs[:explicit] || false,
        href: attrs[:href] || "https://api.spotify.com/v1/tracks/123",
        is_playable: attrs[:is_playable] != false,
        preview_url: attrs[:preview_url] || "https://preview.spotify.com/123",
        track_number: attrs[:track_number] || 1,
        uri: attrs[:uri] || "spotify:track:123",
        popularity: attrs[:popularity] || 50,
        album: attrs[:album] != false ? mock_spotify_album : nil
      })
    end

    def mock_spotify_album(attrs = {})
      OpenStruct.new({
        id: attrs[:id] || "spotify_album_456",
        name: attrs[:name] || "Test Album",
        album_type: attrs[:album_type] || "album",
        release_date: attrs[:release_date] || "2023-01-01",
        total_tracks: attrs[:total_tracks] || 10,
        href: attrs[:href] || "https://api.spotify.com/v1/albums/456",
        uri: attrs[:uri] || "spotify:album:456",
        images: attrs[:images] || [],
        external_urls: attrs[:external_urls] || { spotify: "https://open.spotify.com/album/456" },
        artists: attrs[:artists] != false ? [ mock_spotify_artist ] : []
      })
    end

    def mock_spotify_artist(attrs = {})
      OpenStruct.new({
        id: attrs[:id] || "spotify_artist_789",
        name: attrs[:name] || "Test Artist",
        genres: attrs[:genres] || [ "rock", "indie" ],
        href: attrs[:href] || "https://api.spotify.com/v1/artists/789",
        popularity: attrs[:popularity] || 75,
        uri: attrs[:uri] || "spotify:artist:789",
        images: attrs[:images] || [],
        top_tracks: attrs[:top_tracks] || []
      })
    end

    def mock_spotify_user(attrs = {})
      OpenStruct.new({
        id: attrs[:id] || "test_user",
        display_name: attrs[:display_name] || "Test User",
        email: attrs[:email] || "test@example.com",
        playlists: attrs[:playlists] || [],
        create_playlist!: lambda { |*args| mock_spotify_playlist }
      })
    end

    def mock_spotify_playlist(attrs = {})
      OpenStruct.new({
        id: attrs[:id] || "playlist_999",
        name: attrs[:name] || "Test Playlist",
        tracks: attrs[:tracks] || [],
        uri: attrs[:uri] || "spotify:playlist:playlist_999",
        add_tracks!: lambda { |*args| true },
        remove_tracks!: lambda { |*args| true }
      })
    end

    # Setup a valid authenticated Spotify user for tests
    def setup_spotify_user
      @spotify_user = SpotifyUser.create!(
        username: "test_user",
        spotify_id: "spotify_user_123",
        email: "test@example.com",
        token: "test_token",
        refresh_token: "test_refresh_token",
        token_expires_at: 1.hour.from_now
      )
    end

    # Helper for testing background jobs
    def assert_enqueued_with_job(job_class, args: nil)
      assert_enqueued_jobs 1, only: job_class do
        yield
      end

      if args
        job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        assert_equal args, job[:args]
      end
    end

    # Helper for testing service objects
    def assert_service_success(service_result)
      assert service_result.success?, "Expected service to succeed but got: #{service_result.errors.full_messages.join(', ')}"
    end

    def assert_service_failure(service_result)
      assert service_result.failure?, "Expected service to fail but it succeeded"
    end
  end
end
