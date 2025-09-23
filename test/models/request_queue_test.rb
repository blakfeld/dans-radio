require "test_helper"

class RequestQueueTest < ActiveSupport::TestCase
  setup do
    Rails.application.config.spotify = {
      request_playlist_name: "Test Radio Queue",
      user_name: "test_user"
    }

    RequestQueue.reset!
    @queue = RequestQueue.get
    @track = tracks(:one)
    @track2 = tracks(:two)

    # Setup mock Spotify user
    @spotify_user = spotify_users(:one)
    @spotify_user.update!(username: "test_user")
    @mock_rspotify_user = mock_spotify_user
    @mock_playlist = mock_spotify_playlist(id: "playlist_123", name: "Test Radio Queue")

    SpotifyUser.stubs(:find_by).with(username: "test_user").returns(@spotify_user)
    @spotify_user.stubs(:to_rspotify_user).returns(@mock_rspotify_user)
  end

  teardown do
    RequestQueue.reset!
  end

  # Singleton pattern
  test "get returns singleton instance" do
    queue1 = RequestQueue.get
    queue2 = RequestQueue.get

    assert_equal queue1.id, queue2.id
    assert_equal "Test Radio Queue", queue1.playlist_name
    assert_equal "synced", queue1.sync_status
    assert queue1.active
  end

  test "reset! clears singleton instance" do
    queue1 = RequestQueue.get
    RequestQueue.reset!
    queue2 = RequestQueue.get

    assert_not_equal queue1.object_id, queue2.object_id
  end

  # Associations
  test "belongs to current_track" do
    @queue.current_track = @track
    @queue.save!
    @queue.reload

    assert_equal @track, @queue.current_track
  end

  test "belongs to next_track" do
    @queue.next_track = @track2
    @queue.save!
    @queue.reload

    assert_equal @track2, @queue.next_track
  end

  test "has many song_requests ordered by position" do
    request1 = @queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 2
    )
    request2 = @queue.song_requests.create!(
      track: @track2,
      status: "queued",
      position: 1
    )

    requests = @queue.song_requests
    assert_equal request2, requests.first
    assert_equal request1, requests.second
  end

  # Validations
  test "validates playlist_name presence" do
    @queue.playlist_name = nil
    assert_not @queue.valid?
    assert_includes @queue.errors[:playlist_name], "can't be blank"
  end

  test "validates sync_status inclusion" do
    [ "synced", "out_of_sync", "recovering" ].each do |status|
      @queue.sync_status = status
      assert @queue.valid?, "Status '#{status}' should be valid"
    end

    @queue.sync_status = "invalid"
    assert_not @queue.valid?
  end

  # Queue operations
  test "enqueue adds track to queue" do
    @mock_rspotify_user.stubs(:playlists).returns([ @mock_playlist ])
    @queue.stubs(:spotify_playlist).returns(@mock_playlist)

    assert_difference "@queue.song_requests.count", 1 do
      song_request = @queue.enqueue(@track)

      assert_not_nil song_request
      assert_equal @track, song_request.track
      assert_equal @track.spotify_id, song_request.track_id
      assert_equal @track.artist&.name, song_request.artist
      assert_equal @track.title, song_request.track_title
      assert_equal "queued", song_request.status
      assert_equal 0, song_request.position
      assert_not_nil song_request.queued_at
    end
  end

  test "enqueue increments position for subsequent tracks" do
    @queue.stubs(:spotify_playlist).returns(@mock_playlist)

    request1 = @queue.enqueue(@track)
    request2 = @queue.enqueue(@track2)

    assert_equal 0, request1.position
    assert_equal 1, request2.position
  end

  test "dequeue removes track from queue" do
    @queue.stubs(:spotify_playlist).returns(@mock_playlist)

    song_request = @queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 0
    )

    assert_difference "@queue.song_requests.count", -1 do
      @queue.dequeue(@track)
    end

    assert_nil SongRequest.find_by(id: song_request.id)
  end

  test "dequeue reorders remaining positions" do
    @queue.stubs(:spotify_playlist).returns(@mock_playlist)

    request1 = @queue.song_requests.create!(track: @track, status: "queued", position: 0)
    request2 = @queue.song_requests.create!(track: @track2, status: "queued", position: 1)
    request3 = @queue.song_requests.create!(track: tracks(:one), status: "queued", position: 2)

    @queue.dequeue(@track)

    request2.reload
    request3.reload

    assert_equal 0, request2.position
    assert_equal 1, request3.position
  end

  test "mark_as_playing updates track status" do
    song_request = @queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 0
    )

    @queue.mark_as_playing(@track)

    song_request.reload
    assert_equal "playing", song_request.status
    assert_not_nil song_request.played_at
    assert_equal @track, @queue.reload.current_track
  end

  test "mark_as_playing marks previous playing tracks as played" do
    old_request = @queue.song_requests.create!(
      track: @track2,
      status: "playing",
      position: 0
    )
    new_request = @queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 1
    )

    @queue.mark_as_playing(@track)

    old_request.reload
    new_request.reload

    assert_equal "played", old_request.status
    assert_equal "playing", new_request.status
  end

  test "advance_queue moves to next track" do
    current_request = @queue.song_requests.create!(
      track: @track,
      status: "playing",
      position: 0
    )
    next_request = @queue.song_requests.create!(
      track: @track2,
      status: "queued",
      position: 1
    )

    @queue.update!(current_track: @track)

    @queue.advance_queue

    current_request.reload
    next_request.reload
    @queue.reload

    assert_equal "played", current_request.status
    assert_equal "playing", next_request.status
    assert_equal @track2, @queue.current_track
  end

  test "clear! removes all requests and resets queue" do
    @queue.stubs(:spotify_playlist).returns(@mock_playlist)

    @queue.song_requests.create!(track: @track, status: "queued", position: 0)
    @queue.song_requests.create!(track: @track2, status: "queued", position: 1)
    @queue.update!(current_track: @track, next_track: @track2)

    @queue.clear!
    @queue.reload

    assert_equal 0, @queue.song_requests.count
    assert_nil @queue.current_track
    assert_nil @queue.next_track
    assert_equal 0, @queue.position
  end

  # Track retrieval
  test "current_track returns playing track when no current_track set" do
    playing_request = @queue.song_requests.create!(
      track: @track,
      status: "playing",
      position: 0
    )

    @queue.update!(current_track: nil)

    assert_equal @track, @queue.current_track
  end

  test "next_up returns next queued track" do
    @queue.song_requests.create!(track: @track, status: "playing", position: 0)
    next_request = @queue.song_requests.create!(track: @track2, status: "queued", position: 1)

    assert_equal @track2, @queue.next_up
  end

  test "upcoming_tracks returns tracks in order" do
    playing = @queue.song_requests.create!(track: @track, status: "playing", position: 0)
    queued1 = @queue.song_requests.create!(track: @track2, status: "queued", position: 1)
    queued2 = @queue.song_requests.create!(track: tracks(:one), status: "queued", position: 2)
    played = @queue.song_requests.create!(track: tracks(:two), status: "played", position: 3)

    upcoming = @queue.upcoming_tracks(limit: 10)

    assert_equal 3, upcoming.size
    assert_equal [ @track, @track2, tracks(:one) ], upcoming
    assert_not_includes upcoming, tracks(:two)
  end

  # Sync operations
  test "sync_with_spotify! updates sync status" do
    mock_current = mock_spotify_track(id: @track.spotify_id)
    playlist_tracks = [ mock_spotify_track(id: @track2.spotify_id) ]

    @queue.song_requests.create!(track: @track2, status: "queued", position: 0)

    @queue.sync_with_spotify!(currently_playing: mock_current, playlist_tracks: playlist_tracks)
    @queue.reload

    assert_not_nil @queue.last_sync_at
    assert_in_delta Time.current, @queue.last_sync_at, 2
  end

  test "mark_out_of_sync! sets sync_status" do
    @queue.update!(sync_status: "synced")

    @queue.mark_out_of_sync!
    @queue.reload

    assert_equal "out_of_sync", @queue.sync_status
  end

  test "recover_from_spotify! rebuilds queue from playlist" do
    @queue.stubs(:spotify_playlist).returns(@mock_playlist)

    # Setup mock playlist tracks
    mock_tracks = [
      mock_spotify_track(id: @track.spotify_id),
      mock_spotify_track(id: @track2.spotify_id)
    ]
    @mock_playlist.stubs(:tracks).returns(mock_tracks)

    # Clear existing requests
    @queue.song_requests.destroy_all

    @queue.recover_from_spotify!
    @queue.reload

    assert_equal "synced", @queue.sync_status
    assert_equal 2, @queue.song_requests.count

    requests = @queue.song_requests.order(:position)
    assert_equal @track, requests.first.track
    assert_equal @track2, requests.second.track
    assert_equal "queued", requests.first.status
    assert_equal "queued", requests.second.status
  end

  test "ensure_playlist_exists! creates playlist if needed" do
    @mock_rspotify_user.stubs(:playlists).returns([])
    @mock_rspotify_user.stubs(:create_playlist!)
      .with("Test Radio Queue", public: false)
      .returns(@mock_playlist)

    result = @queue.ensure_playlist_exists!

    assert_equal @mock_playlist, result
    assert_equal "playlist_123", @queue.reload.playlist_id
  end

  test "ensure_playlist_exists! finds existing playlist" do
    existing_playlist = mock_spotify_playlist(id: "existing_123", name: "Test Radio Queue")
    @mock_rspotify_user.stubs(:playlists).returns([ existing_playlist ])

    result = @queue.ensure_playlist_exists!

    assert_equal existing_playlist, result
    assert_equal "existing_123", @queue.reload.playlist_id
  end
end
