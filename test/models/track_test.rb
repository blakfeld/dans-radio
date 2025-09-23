require "test_helper"

class TrackTest < ActiveSupport::TestCase
  setup do
    @artist = artists(:one)
    @album = albums(:one)
    @track = tracks(:one)
  end

  # Associations
  test "belongs to album" do
    assert_respond_to @track, :album
    assert_instance_of Album, @track.album
  end

  test "has one artist through album" do
    assert_respond_to @track, :artist
    assert_instance_of Artist, @track.artist
  end

  # Class methods
  test "find_by_spotify_id returns existing track" do
    track = Track.find_by_spotify_id(@track.spotify_id)
    assert_equal @track, track
  end

  test "find_by_spotify_id fetches from Spotify when not found locally" do
    spotify_track = mock_spotify_track(id: "new_track_123", name: "New Song")
    album_record = albums(:one)

    # Mock the Spotify API calls
    RSpotify::Track.expects(:find).with("new_track_123").returns(spotify_track)
    Album.expects(:find_by_spotify_id).returns(album_record)

    track = Track.find_by_spotify_id("new_track_123")

    assert_not_nil track
    assert_equal "new_track_123", track.spotify_id
    assert_equal "New Song", track.title
  end

  test "find_by_spotify_id returns nil for blank spotify_id" do
    assert_nil Track.find_by_spotify_id(nil)
    assert_nil Track.find_by_spotify_id("")
  end

  test "find_by_spotify_id handles Spotify API errors gracefully" do
    RSpotify::Track.expects(:find).raises(StandardError.new("API Error"))

    assert_nil Track.find_by_spotify_id("error_track")
  end

  test "create_from_spotify creates track with all attributes" do
    spotify_track = mock_spotify_track(
      id: "create_test_123",
      name: "Created Song",
      duration_ms: 240000,
      explicit: true,
      track_number: 5,
      uri: "spotify:track:create_test_123"
    )

    album_record = albums(:one)
    Album.expects(:find_by_spotify_id).returns(album_record)

    track = Track.create_from_spotify(spotify_track)

    assert_not_nil track
    assert_equal "create_test_123", track.spotify_id
    assert_equal "Created Song", track.title
    assert_equal 240000, track.duration_ms
    assert_equal true, track.explicit
    assert_equal 5, track.track_number
    assert_equal album_record.id, track.album_id
  end

  test "create_from_spotify handles invalid data" do
    spotify_track = mock_spotify_track(id: nil)

    track = Track.create_from_spotify(spotify_track)
    assert_nil track
  end

  # Instance methods
  test "to_rspotify_track returns RSpotify track object" do
    RSpotify::Track.expects(:find).with(@track.spotify_id).returns(mock_spotify_track)

    rspotify_track = @track.to_rspotify_track
    assert_not_nil rspotify_track
  end

  test "update_from_spotify updates track attributes" do
    updated_spotify_track = mock_spotify_track(
      id: @track.spotify_id,
      name: "Updated Title",
      duration_ms: 300000,
      explicit: true
    )

    @track.expects(:to_rspotify_track).returns(updated_spotify_track)
    Album.expects(:find_by_spotify_id).returns(@album)

    result = @track.update_from_spotify

    assert result
    @track.reload
    assert_equal "Updated Title", @track.title
    assert_equal 300000, @track.duration_ms
    assert_equal true, @track.explicit
  end

  test "update_from_spotify handles errors gracefully" do
    @track.expects(:to_rspotify_track).raises(StandardError.new("API Error"))

    result = @track.update_from_spotify
    assert_equal false, result
  end

  test "duration_formatted returns correct format" do
    @track.duration_ms = 180000 # 3 minutes
    assert_equal "3:00", @track.duration_formatted

    @track.duration_ms = 215000 # 3:35
    assert_equal "3:35", @track.duration_formatted

    @track.duration_ms = 65000 # 1:05
    assert_equal "1:05", @track.duration_formatted
  end

  test "duration_formatted returns nil when duration_ms is nil" do
    @track.duration_ms = nil
    assert_nil @track.duration_formatted
  end
end
