require "test_helper"

class RequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    RequestQueue.reset!
    @queue = RequestQueue.get
    @artist = artists(:one)
    @album = albums(:one)
    @track = tracks(:one)
  end

  teardown do
    RequestQueue.reset!
  end

  # New action tests
  test "should get new" do
    get new_request_url(track_id: @track.id)
    assert_response :success
    assert_not_nil assigns(:request)
    assert_equal @track, assigns(:track)
  end

  test "redirects when in cooldown" do
    # Set recent request time
    get new_request_url(track_id: @track.id),
        session: { last_request_time: 1.minute.ago.to_s }

    assert_redirected_to browse_path
    assert_match /Please wait .+ seconds/, flash[:alert]
  end

  test "shows new request form when not in cooldown" do
    get new_request_url(track_id: @track.id),
        session: { last_request_time: 10.minutes.ago.to_s }

    assert_response :success
    assert_not_nil assigns(:request)
  end

  test "handles missing track in new action" do
    get new_request_url(track_id: 999999)
    assert_redirected_to browse_path
    assert_equal "Track not found", flash[:alert]
  end

  # Create action tests
  test "creates song request successfully" do
    EnqueueSongRequest.any_instance.expects(:call)

    assert_difference("SongRequest.count", 1) do
      post requests_url, params: { track_id: @track.id }
    end

    assert_redirected_to confirmation_requests_path

    request = SongRequest.last
    assert_equal @track, request.track
    assert_equal @track.spotify_id, request.track_id
    assert_equal @track.title, request.track_title
    assert_equal @track.artist&.name, request.artist
    assert_equal "pending", request.status
    assert_equal @queue, request.request_queue

    # Check session updates
    assert_not_nil session[:last_request_time]
    assert_equal request.id, session[:last_request_id]
  end

  test "sets correct position for new request" do
    # Create existing requests
    @queue.song_requests.create!(
      track: tracks(:two),
      status: "queued",
      position: 5
    )

    EnqueueSongRequest.any_instance.expects(:call)

    post requests_url, params: { track_id: @track.id }

    request = SongRequest.last
    assert_equal 6, request.position
  end

  test "rejects request when in cooldown" do
    assert_no_difference("SongRequest.count") do
      post requests_url, params: { track_id: @track.id }, session: { last_request_time: 1.minute.ago.to_s }
    end

    assert_redirected_to browse_path
    assert_match /Please wait before making another request/, flash[:alert]
  end

  test "handles enqueue errors gracefully" do
    EnqueueSongRequest.any_instance.expects(:call)
      .raises(StandardError.new("Enqueue error"))

    # Should still create the request
    assert_difference("SongRequest.count", 1) do
      post requests_url, params: { track_id: @track.id }
    end

    assert_redirected_to confirmation_requests_path
  end

  test "handles save failures" do
    # Make track invalid somehow
    SongRequest.any_instance.stubs(:save).returns(false)
    SongRequest.any_instance.stubs(:errors).returns(
      double(full_messages: [ "Test error" ])
    )

    assert_no_difference("SongRequest.count") do
      post requests_url, params: { track_id: @track.id }
    end

    assert_redirected_to browse_path
    assert_match /Unable to create request/, flash[:alert]
  end

  # Confirmation action tests
  test "shows confirmation page" do
    request = @queue.song_requests.create!(
      track: @track,
      status: "pending",
      position: 1
    )

    mock_queue_status = {
      queue_position: 1,
      currently_playing: @track,
      next_tracks: [ @track ]
    }
    GetQueuePosition.expects(:call).returns(mock_queue_status)

    get confirmation_requests_url, params: {}, session: { last_request_id: request.id }

    assert_response :success
    assert_equal request, assigns(:request)
    assert_equal mock_queue_status, assigns(:queue_status)
    assert_equal 1, assigns(:queue_position)
  end

  test "confirmation handles missing request" do
    GetQueuePosition.expects(:call).returns({})

    get confirmation_requests_url, params: {}, session: { last_request_id: 999999 }

    assert_response :success
    assert_nil assigns(:request)
  end

  test "confirmation works without session request id" do
    GetQueuePosition.expects(:call).returns({})

    get confirmation_requests_url

    assert_response :success
    assert_nil assigns(:request)
  end

  # Index action tests
  test "lists active requests" do
    # Create various requests
    playing = @queue.song_requests.create!(
      track: @track,
      status: "playing",
      position: 0
    )
    queued = @queue.song_requests.create!(
      track: tracks(:two),
      status: "queued",
      position: 1
    )
    pending = @queue.song_requests.create!(
      track: tracks(:one),
      status: "pending",
      position: 2
    )
    played = @queue.song_requests.create!(
      track: tracks(:two),
      status: "played",
      position: 3
    )

    get requests_url

    assert_response :success

    pending_requests = assigns(:pending_requests)
    currently_playing = assigns(:currently_playing)

    assert_includes pending_requests, queued
    assert_includes pending_requests, pending
    assert_includes pending_requests, playing
    assert_not_includes pending_requests, played

    assert_equal playing, currently_playing
  end

  test "orders requests by position" do
    req3 = @queue.song_requests.create!(
      track: tracks(:one),
      status: "queued",
      position: 3
    )
    req1 = @queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 1
    )
    req2 = @queue.song_requests.create!(
      track: tracks(:two),
      status: "queued",
      position: 2
    )

    get requests_url

    pending_requests = assigns(:pending_requests)
    assert_equal [ req1, req2, req3 ], pending_requests.to_a
  end

  test "includes track information" do
    @queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 1
    )

    get requests_url

    assert_response :success
    # Should preload tracks to avoid N+1
    assert_not_nil assigns(:pending_requests).first.track
  end

  # Cooldown helper tests
  test "cooldown period is 5 minutes" do
    controller = RequestsController.new
    assert_equal 5.minutes, controller.send(:cooldown_period)
  end

  test "calculates remaining cooldown correctly" do
    last_request = 3.minutes.ago

    get new_request_url(track_id: @track.id),
        session: { last_request_time: last_request.to_s }

    cooldown_remaining = assigns(:cooldown_remaining)
    assert_in_delta 120, cooldown_remaining, 2 # ~2 minutes remaining
  end

  test "no cooldown for first request" do
    get new_request_url(track_id: @track.id)

    assert_response :success
    assert assigns(:can_request)
    assert_nil assigns(:cooldown_remaining)
  end
end
