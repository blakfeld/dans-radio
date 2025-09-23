require "test_helper"

class UpdatePlayheadTest < ActiveSupport::TestCase
  setup do
    RequestQueue.reset!
    @request_queue = RequestQueue.get
    @track1 = tracks(:one)
    @track2 = tracks(:two)

    # Create a playing track
    @playing_request = @request_queue.song_requests.create!(
      track: @track1,
      status: "playing",
      position: 0
    )

    # Create a queued track
    @queued_request = @request_queue.song_requests.create!(
      track: @track2,
      status: "queued",
      position: 1
    )

    @request_queue.update!(current_track: @track1)
  end

  teardown do
    RequestQueue.reset!
  end

  test "updates progress when track is still playing" do
    currently_playing = {
      is_playing: true,
      item: mock_spotify_track(
        id: @track1.spotify_id,
        duration_ms: 180000
      ),
      progress_ms: 60000,
      context: { uri: "spotify:playlist:test" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)

    service = UpdatePlayhead.new
    result = service.call

    assert result[:success]
    assert_equal @track1.spotify_id, result[:track_id]
    assert_equal 60000, result[:progress_ms]
    assert_equal 180000, result[:duration_ms]
    assert_equal "playing", result[:status]
    assert_nil result[:next_track_id]
  end

  test "advances queue when track has finished" do
    currently_playing = {
      is_playing: true,
      item: mock_spotify_track(
        id: @track2.spotify_id,  # Now playing the second track
        duration_ms: 200000
      ),
      progress_ms: 10000,
      context: { uri: "spotify:playlist:test" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)

    service = UpdatePlayhead.new
    result = service.call

    assert result[:success]
    assert_equal @track2.spotify_id, result[:track_id]

    # Check that the queue was advanced
    @playing_request.reload
    @queued_request.reload
    assert_equal "played", @playing_request.status
    assert_equal "playing", @queued_request.status
  end

  test "handles paused playback" do
    currently_playing = {
      is_playing: false,
      item: mock_spotify_track(
        id: @track1.spotify_id,
        duration_ms: 180000
      ),
      progress_ms: 60000,
      context: { uri: "spotify:playlist:test" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)

    service = UpdatePlayhead.new
    result = service.call

    assert result[:success]
    assert_equal "paused", result[:status]
  end

  test "handles nothing playing" do
    Spotify::GetCurrentlyPlaying.expects(:call).returns(nil)

    service = UpdatePlayhead.new
    result = service.call

    assert result[:success]
    assert_equal "stopped", result[:status]
    assert_nil result[:track_id]
  end

  test "identifies when track is near end" do
    currently_playing = {
      is_playing: true,
      item: mock_spotify_track(
        id: @track1.spotify_id,
        duration_ms: 180000
      ),
      progress_ms: 175000,  # 5 seconds from end
      context: { uri: "spotify:playlist:test" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)

    service = UpdatePlayhead.new
    result = service.call

    assert result[:success]
    assert result[:near_end]
  end

  test "handles unknown track playing" do
    unknown_track = mock_spotify_track(
      id: "unknown_track_123",
      name: "Unknown Song",
      duration_ms: 180000
    )

    currently_playing = {
      is_playing: true,
      item: unknown_track,
      progress_ms: 60000,
      context: { uri: "spotify:playlist:test" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)
    Track.expects(:find_by_spotify_id).with("unknown_track_123").returns(nil)

    service = UpdatePlayhead.new
    result = service.call

    assert result[:success]
    assert_equal "unknown_track_123", result[:track_id]
    assert_equal "unknown", result[:status]
  end

  test "handles API errors gracefully" do
    Spotify::GetCurrentlyPlaying.expects(:call).raises(StandardError.new("API Error"))

    service = UpdatePlayhead.new
    result = service.call

    assert_not result[:success]
    assert_equal "API Error", result[:error]
  end

  test "broadcasts updates via ActionCable" do
    currently_playing = {
      is_playing: true,
      item: mock_spotify_track(
        id: @track1.spotify_id,
        duration_ms: 180000
      ),
      progress_ms: 60000,
      context: { uri: "spotify:playlist:test" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)
    ActionCable.server.expects(:broadcast).with(
      "now_playing",
      hash_including(
        track_id: @track1.spotify_id,
        progress_ms: 60000,
        duration_ms: 180000,
        is_playing: true
      )
    )

    service = UpdatePlayhead.new
    service.call
  end

  test "correctly calculates progress percentage" do
    currently_playing = {
      is_playing: true,
      item: mock_spotify_track(
        id: @track1.spotify_id,
        duration_ms: 200000
      ),
      progress_ms: 50000,  # 25% complete
      context: { uri: "spotify:playlist:test" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)

    service = UpdatePlayhead.new
    result = service.call

    assert_equal 25.0, result[:progress_percentage]
  end

  test "handles transition between playlists" do
    # Track from different context playing
    currently_playing = {
      is_playing: true,
      item: mock_spotify_track(
        id: "different_track_123",
        duration_ms: 180000
      ),
      progress_ms: 60000,
      context: { uri: "spotify:playlist:different_playlist" }
    }

    Spotify::GetCurrentlyPlaying.expects(:call).returns(currently_playing)
    Track.expects(:find_by_spotify_id).with("different_track_123").returns(nil)

    service = UpdatePlayhead.new
    result = service.call

    assert result[:success]
    assert_equal "different_playlist", result[:context]
  end
end

