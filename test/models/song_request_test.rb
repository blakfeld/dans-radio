require "test_helper"

class SongRequestTest < ActiveSupport::TestCase
  setup do
    @request_queue = RequestQueue.get
    @track = tracks(:one)
    @song_request = song_requests(:one)
    @song_request.update!(request_queue: @request_queue, track: @track, status: "pending")
  end

  teardown do
    RequestQueue.reset!
  end

  # Associations
  test "belongs to request_queue" do
    assert_respond_to @song_request, :request_queue
    assert_instance_of RequestQueue, @song_request.request_queue
  end

  test "belongs to track (optional)" do
    assert_respond_to @song_request, :track
    assert_instance_of Track, @song_request.track

    # Test optional nature
    @song_request.track = nil
    assert @song_request.valid?
  end

  # Validations
  test "validates status inclusion" do
    SongRequest::STATUSES.each do |status|
      @song_request.status = status
      assert @song_request.valid?, "Status '#{status}' should be valid"
    end

    @song_request.status = "invalid_status"
    assert_not @song_request.valid?
    assert_includes @song_request.errors[:status], "is not included in the list"
  end

  test "validates position is non-negative" do
    @song_request.position = 0
    assert @song_request.valid?

    @song_request.position = 5
    assert @song_request.valid?

    @song_request.position = -1
    assert_not @song_request.valid?
    assert_includes @song_request.errors[:position], "must be greater than or equal to 0"
  end

  test "allows nil position" do
    @song_request.position = nil
    assert @song_request.valid?
  end

  # Scopes
  test "pending scope returns pending requests" do
    @song_request.update!(status: "pending")
    assert_includes SongRequest.pending, @song_request

    @song_request.update!(status: "queued")
    assert_not_includes SongRequest.pending, @song_request
  end

  test "queued scope returns queued requests" do
    @song_request.update!(status: "queued")
    assert_includes SongRequest.queued, @song_request

    @song_request.update!(status: "pending")
    assert_not_includes SongRequest.queued, @song_request
  end

  test "playing scope returns playing requests" do
    @song_request.update!(status: "playing")
    assert_includes SongRequest.playing, @song_request

    @song_request.update!(status: "played")
    assert_not_includes SongRequest.playing, @song_request
  end

  test "played scope returns played requests" do
    @song_request.update!(status: "played")
    assert_includes SongRequest.played, @song_request

    @song_request.update!(status: "playing")
    assert_not_includes SongRequest.played, @song_request
  end

  test "active scope returns active requests" do
    [ "pending", "queued", "playing" ].each do |status|
      @song_request.update!(status: status)
      assert_includes SongRequest.active, @song_request, "Status '#{status}' should be included in active scope"
    end

    [ "played", "failed", "recovered" ].each do |status|
      @song_request.update!(status: status)
      assert_not_includes SongRequest.active, @song_request, "Status '#{status}' should not be included in active scope"
    end
  end

  # Instance methods
  test "spotify_track returns RSpotify track object" do
    mock_track = mock_spotify_track
    @track.expects(:to_rspotify_track).returns(mock_track)

    result = @song_request.spotify_track
    assert_equal mock_track, result
  end

  test "spotify_track returns nil when track is nil" do
    @song_request.track = nil
    assert_nil @song_request.spotify_track
  end

  test "playing? returns true when status is playing" do
    @song_request.status = "playing"
    assert @song_request.playing?

    @song_request.status = "queued"
    assert_not @song_request.playing?
  end

  test "played? returns true when status is played" do
    @song_request.status = "played"
    assert @song_request.played?

    @song_request.status = "playing"
    assert_not @song_request.played?
  end

  test "active? returns true for active statuses" do
    [ "pending", "queued", "playing" ].each do |status|
      @song_request.status = status
      assert @song_request.active?, "Should be active when status is '#{status}'"
    end

    [ "played", "failed", "recovered" ].each do |status|
      @song_request.status = status
      assert_not @song_request.active?, "Should not be active when status is '#{status}'"
    end
  end

  # Integration tests
  test "can create song request with all attributes" do
    new_request = SongRequest.create!(
      request_queue: @request_queue,
      track: @track,
      track_id: @track.spotify_id,
      artist: @track.artist&.name,
      track_title: @track.title,
      track_uri: @track.uri,
      status: "pending",
      position: 10,
      requester_name: "Test User",
      requester_email: "test@example.com"
    )

    assert new_request.persisted?
    assert_equal @request_queue, new_request.request_queue
    assert_equal @track, new_request.track
    assert_equal "pending", new_request.status
    assert_equal 10, new_request.position
  end

  test "can track lifecycle through status changes" do
    @song_request.update!(status: "pending")
    assert @song_request.active?
    assert_not @song_request.playing?
    assert_not @song_request.played?

    @song_request.update!(status: "queued", queued_at: Time.current)
    assert @song_request.active?
    assert_not @song_request.playing?
    assert_not @song_request.played?

    @song_request.update!(status: "playing")
    assert @song_request.active?
    assert @song_request.playing?
    assert_not @song_request.played?

    @song_request.update!(status: "played", played_at: Time.current)
    assert_not @song_request.active?
    assert_not @song_request.playing?
    assert @song_request.played?
  end
end
