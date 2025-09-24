require "test_helper"

class ManageCurrentlyPlayingTest < ActiveSupport::TestCase
  setup do
    RequestQueue.reset!
    @request_queue = RequestQueue.get
    @track = tracks(:one)

    # Mock Spotify playlists
    @requests_playlist = mock_spotify_playlist(
      id: "requests_123",
      name: "Dans Radio Queue",
      uri: "spotify:playlist:requests_123"
    )
    @radio_playlist = mock_spotify_playlist(
      id: "radio_456",
      name: "Dans Radio",
      uri: "spotify:playlist:radio_456"
    )

    Rails.application.config.spotify = {
      request_playlist_name: "Dans Radio Queue",
      radio_playlist_name: "Dans Radio"
    }
  end

  teardown do
    RequestQueue.reset!
  end

  test "uses request playlist when there are active requests" do
    # Create active requests
    @request_queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 0
    )

    # Mock Spotify API calls
    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio Queue").returns(@requests_playlist)
    Spotify::GetCurrentlyPlaying.expects(:call).returns(nil)

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue)
    result = service.call

    assert_equal false, result[:changed]
    assert_equal "Dans Radio Queue", result[:playlist]
  end

  test "uses radio playlist when no active requests" do
    # Ensure no active requests
    @request_queue.song_requests.destroy_all

    # Mock Spotify API calls
    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio").returns(@radio_playlist)
    Spotify::GetCurrentlyPlaying.expects(:call).returns(nil)

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue)
    result = service.call

    assert_equal false, result[:changed]
    assert_equal "Dans Radio", result[:playlist]
  end

  test "doesn't change playlist when already playing correct one" do
    @request_queue.song_requests.create!(track: @track, status: "playing")

    currently_playing = {
      is_playing: true,
      context_uri: "spotify:playlist:requests_123",
      track: { name: "Current Song" }
    }

    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio Queue").returns(@requests_playlist)
    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue)
    result = service.call

    assert_equal false, result[:changed]
    assert_equal "Dans Radio Queue", result[:playlist]
  end

  test "changes playlist when playing wrong one" do
    @request_queue.song_requests.create!(track: @track, status: "queued")

    currently_playing = {
      is_playing: true,
      context_uri: "spotify:playlist:wrong_playlist",
      track: { name: "Current Song" }
    }

    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio Queue").returns(@requests_playlist)
    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)
    Spotify::PlayPlaylist.expects(:call).with(playlist: @requests_playlist).returns(true)

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue)
    result = service.call

    assert_equal true, result[:changed]
    assert_equal "Dans Radio Queue", result[:playlist]
  end

  test "auto-starts radio playlist when enabled and queue is empty" do
    @request_queue.song_requests.destroy_all

    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio").returns(@radio_playlist)
    Spotify::GetCurrentlyPlaying.expects(:call).returns(nil)
    Spotify::PlayPlaylist.expects(:call).with(playlist: @radio_playlist).returns(true)

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue, auto_start: true)
    result = service.call

    assert_equal true, result[:changed]
    assert_equal "Dans Radio", result[:playlist]
    assert_equal true, result[:auto_started]
  end

  test "doesn't auto-start when disabled" do
    @request_queue.song_requests.destroy_all

    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio").returns(@radio_playlist)
    Spotify::GetCurrentlyPlaying.expects(:call).returns(nil)
    Spotify::PlayPlaylist.expects(:call).never

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue, auto_start: false)
    result = service.call

    assert_equal false, result[:changed]
    assert_equal "Dans Radio", result[:playlist]
    assert_equal "spotify:playlist:radio_456", result[:should_play]
  end

  test "handles missing request playlist gracefully" do
    @request_queue.song_requests.create!(track: @track, status: "queued")

    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio Queue").returns(nil)

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue)
    result = service.call

    assert_equal false, result[:changed]
    assert_nil result[:playlist]
    assert_equal "Request playlist not found: Dans Radio Queue", result[:error]
  end

  test "handles missing radio playlist gracefully" do
    @request_queue.song_requests.destroy_all

    Spotify::GetPlaylist.expects(:call).with(name: "Dans Radio").returns(nil)

    service = ManageCurrentlyPlaying.new(request_queue: @request_queue)
    result = service.call

    assert_equal false, result[:changed]
    assert_nil result[:playlist]
    assert_equal "Radio playlist not found: Dans Radio", result[:error]
  end
end
