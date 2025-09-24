require "test_helper"

class ProcessRequestQueueJobTest < ActiveJob::TestCase
  setup do
    RequestQueue.reset!
    @request_queue = RequestQueue.get
    @track1 = tracks(:one)
    @track2 = tracks(:two)

    # Mock Spotify playlist
    @mock_playlist = mock_spotify_playlist(id: "playlist_123")
    @request_queue.stubs(:spotify_playlist).returns(@mock_playlist)
  end

  teardown do
    RequestQueue.reset!
  end

  test "processes synced queue successfully" do
    # Setup queue with playing and queued tracks
    playing_request = @request_queue.song_requests.create!(
      track: @track1,
      status: "playing",
      position: 0
    )
    queued_request = @request_queue.song_requests.create!(
      track: @track2,
      status: "queued",
      position: 1
    )

    @request_queue.update!(sync_status: "synced")

    # Mock the sync call
    sync_result = {
      queue_position: 0,
      currently_playing_spotify: {
        is_playing: true,
        item: mock_spotify_track(id: @track1.spotify_id)
      },
      spotify_queue: [ @track2 ]
    }

    GetQueuePosition.expects(:call).with(request_queue: @request_queue).returns(sync_result)

    perform_enqueued_jobs do
      ProcessRequestQueueJob.perform_later
    end

    # Verify the job ran without errors
    assert_performed_jobs 1
  end

  test "handles out of sync status" do
    @request_queue.update!(sync_status: "out_of_sync")

    sync_result = { error: nil }
    GetQueuePosition.expects(:call).returns(sync_result)

    # Should trigger recovery
    SyncQueuePlaylistJob.expects(:perform_later).with(@request_queue.id)

    perform_enqueued_jobs do
      ProcessRequestQueueJob.perform_later
    end
  end

  test "handles recovering status" do
    @request_queue.update!(sync_status: "recovering")

    sync_result = { error: nil }
    GetQueuePosition.expects(:call).returns(sync_result)

    # Should schedule retry soon
    assert_nothing_raised do
      perform_enqueued_jobs do
        ProcessRequestQueueJob.perform_later
      end
    end
  end

  test "processes pending requests" do
    # Create pending requests
    pending1 = @request_queue.song_requests.create!(
      track: @track1,
      status: "pending",
      position: 0
    )
    pending2 = @request_queue.song_requests.create!(
      track: @track2,
      status: "pending",
      position: 1
    )

    @request_queue.update!(sync_status: "synced")

    sync_result = {
      queue_position: 0,
      currently_playing_spotify: nil,
      spotify_queue: []
    }

    GetQueuePosition.expects(:call).returns(sync_result)
    @mock_playlist.expects(:add_tracks!).with([ anything ])

    perform_enqueued_jobs do
      ProcessRequestQueueJob.perform_later
    end

    # Check that pending requests were processed
    pending1.reload
    assert_equal "queued", pending1.status
    assert_not_nil pending1.queued_at
  end

  test "handles sync errors with retry" do
    sync_result = { error: "Spotify API error" }

    GetQueuePosition.expects(:call).returns(sync_result)
    Rails.logger.expects(:error).with(/Queue sync failed/)

    # Should not raise but log error
    assert_nothing_raised do
      perform_enqueued_jobs do
        ProcessRequestQueueJob.perform_later
      end
    end
  end

  test "handles exceptions gracefully" do
    GetQueuePosition.expects(:call).raises(StandardError.new("Unexpected error"))
    Rails.logger.expects(:error).with(/ProcessRequestQueueJob failed/)

    assert_nothing_raised do
      perform_enqueued_jobs do
        ProcessRequestQueueJob.perform_later
      end
    end
  end

  test "ensures spotify queue is filled to minimum" do
    # Create less than minimum tracks in queue
    @request_queue.song_requests.create!(
      track: @track1,
      status: "queued",
      position: 0
    )

    @request_queue.update!(sync_status: "synced")

    sync_result = {
      queue_position: 0,
      currently_playing_spotify: {
        is_playing: true,
        item: mock_spotify_track(id: @track1.spotify_id)
      },
      spotify_queue: []
    }

    GetQueuePosition.expects(:call).returns(sync_result)

    # Should check if more tracks need to be added
    perform_enqueued_jobs do
      ProcessRequestQueueJob.perform_later
    end
  end

  test "removes played tracks older than threshold" do
    # Create old played tracks
    old_played = @request_queue.song_requests.create!(
      track: @track1,
      status: "played",
      position: 0,
      played_at: 2.hours.ago
    )

    recent_played = @request_queue.song_requests.create!(
      track: @track2,
      status: "played",
      position: 1,
      played_at: 10.minutes.ago
    )

    @request_queue.update!(sync_status: "synced")

    sync_result = {
      queue_position: 0,
      currently_playing_spotify: nil,
      spotify_queue: []
    }

    GetQueuePosition.expects(:call).returns(sync_result)

    perform_enqueued_jobs do
      ProcessRequestQueueJob.perform_later
    end

    # Old played track should be removed
    assert_nil SongRequest.find_by(id: old_played.id)
    # Recent played track should remain
    assert_not_nil SongRequest.find_by(id: recent_played.id)
  end

  test "schedules next check appropriately when playing" do
    playing_request = @request_queue.song_requests.create!(
      track: @track1,
      status: "playing",
      position: 0
    )

    @request_queue.update!(sync_status: "synced")

    # Mock track with 30 seconds remaining
    sync_result = {
      queue_position: 0,
      currently_playing_spotify: {
        is_playing: true,
        item: mock_spotify_track(
          id: @track1.spotify_id,
          duration_ms: 180000
        ),
        progress_ms: 150000  # 30 seconds left
      },
      spotify_queue: []
    }

    GetQueuePosition.expects(:call).returns(sync_result)

    # Should schedule next check based on remaining time
    perform_enqueued_jobs do
      ProcessRequestQueueJob.perform_later
    end
  end

  test "schedules next check when not playing" do
    @request_queue.update!(sync_status: "synced")

    sync_result = {
      queue_position: 0,
      currently_playing_spotify: {
        is_playing: false
      },
      spotify_queue: []
    }

    GetQueuePosition.expects(:call).returns(sync_result)

    # Should schedule check in default interval
    perform_enqueued_jobs do
      ProcessRequestQueueJob.perform_later
    end
  end
end
