require "test_helper"

class ArtistTest < ActiveSupport::TestCase
  setup do
    @artist = artists(:one)
  end

  # Associations
  test "has many albums" do
    assert_respond_to @artist, :albums
    assert_kind_of ActiveRecord::Associations::CollectionProxy, @artist.albums
  end

  test "has many tracks through albums" do
    assert_respond_to @artist, :tracks
    assert_kind_of ActiveRecord::Associations::CollectionProxy, @artist.tracks
  end

  # Serialization
  test "serializes images as JSON" do
    @artist.images = [ { url: "http://example.com/artist.jpg", height: 640, width: 640 } ]
    @artist.save!
    @artist.reload
    assert_equal Array, @artist.images.class
    assert_equal "http://example.com/artist.jpg", @artist.images.first["url"]
  end

  test "serializes genres as JSON" do
    @artist.genres = [ "rock", "indie", "alternative" ]
    @artist.save!
    @artist.reload
    assert_equal Array, @artist.genres.class
    assert_includes @artist.genres, "rock"
    assert_includes @artist.genres, "indie"
  end

  # Instance methods
  test "to_rspotify_artist returns RSpotify artist object" do
    mock_artist = mock_spotify_artist(id: @artist.spotify_id)
    RSpotify::Artist.expects(:find).with(@artist.spotify_id).returns(mock_artist)

    rspotify_artist = @artist.to_rspotify_artist
    assert_equal mock_artist, rspotify_artist
  end

  # Class methods
  test "create_from_spotify creates artist with all attributes" do
    spotify_artist = mock_spotify_artist(
      id: "new_artist_123",
      name: "New Artist",
      uri: "spotify:artist:new_artist_123",
      href: "https://api.spotify.com/v1/artists/new_artist_123"
    )

    artist = Artist.create_from_spotify(spotify_artist)

    assert_not_nil artist
    assert artist.persisted?
    assert_equal "new_artist_123", artist.spotify_id
    assert_equal "New Artist", artist.name
    assert_equal "spotify:artist:new_artist_123", artist.uri
    assert_equal "https://api.spotify.com/v1/artists/new_artist_123", artist.href
  end

  test "create_from_spotify returns nil for nil input" do
    assert_nil Artist.create_from_spotify(nil)
  end

  test "create_from_spotify handles validation errors" do
    spotify_artist = mock_spotify_artist(id: nil)

    artist = Artist.create_from_spotify(spotify_artist)
    assert_nil artist
  end

  test "update_from_spotify updates artist attributes" do
    updated_spotify_artist = mock_spotify_artist(
      id: @artist.spotify_id,
      name: "Updated Artist Name",
      uri: "spotify:artist:updated",
      href: "https://api.spotify.com/v1/artists/updated"
    )

    @artist.expects(:to_rspotify_artist).returns(updated_spotify_artist)

    result = @artist.update_from_spotify

    assert result
    @artist.reload
    assert_equal "Updated Artist Name", @artist.name
    assert_equal "spotify:artist:updated", @artist.uri
    assert_equal "https://api.spotify.com/v1/artists/updated", @artist.href
  end

  test "update_from_spotify returns false when Spotify artist not found" do
    @artist.expects(:to_rspotify_artist).returns(nil)

    result = @artist.update_from_spotify
    assert_equal false, result
  end

  test "update_from_spotify handles errors gracefully" do
    @artist.expects(:to_rspotify_artist).raises(StandardError.new("API Error"))

    result = @artist.update_from_spotify
    assert_equal false, result
  end

  # Top tracks functionality
  test "top_tracks returns cached top tracks when available" do
    track1 = tracks(:one)
    track2 = tracks(:two)
    track1.update!(is_top_track: true, popularity: 90)
    track2.update!(is_top_track: true, popularity: 85)

    top_tracks = @artist.top_tracks(limit: 2)

    assert_equal 2, top_tracks.size
    assert_includes top_tracks, track1
    assert_includes top_tracks, track2
    assert_equal track1, top_tracks.first # Higher popularity first
  end

  test "top_tracks fetches from Spotify when no cached tracks" do
    Track.update_all(is_top_track: false)

    @artist.expects(:fetch_and_cache_top_tracks).with(limit: 5).returns([])

    @artist.top_tracks
  end

  test "fetch_and_cache_top_tracks retrieves and stores tracks from Spotify" do
    spotify_artist = mock_spotify_artist(id: @artist.spotify_id)
    spotify_track1 = mock_spotify_track(
      id: "top_track_1",
      name: "Hit Song 1",
      popularity: 95
    )
    spotify_track2 = mock_spotify_track(
      id: "top_track_2",
      name: "Hit Song 2",
      popularity: 90
    )

    @artist.expects(:to_rspotify_artist).returns(spotify_artist)
    spotify_artist.expects(:top_tracks).with("US").returns([ spotify_track1, spotify_track2 ])

    # Mock album creation for the tracks
    mock_album = albums(:one)
    Album.stubs(:find_by).returns(mock_album)
    Album.stubs(:find_or_create_by).returns(mock_album)

    # Mock track creation
    Track.stubs(:find_by).returns(nil)
    track1 = Track.new(spotify_id: "top_track_1", title: "Hit Song 1", album: mock_album)
    track2 = Track.new(spotify_id: "top_track_2", title: "Hit Song 2", album: mock_album)
    Track.stubs(:find_or_create_by).returns(track1, track2)
    track1.stubs(:update!).returns(true)
    track2.stubs(:update!).returns(true)

    result = @artist.fetch_and_cache_top_tracks(limit: 2)

    assert_equal 2, result.size
  end

  test "fetch_and_cache_top_tracks handles missing spotify_id" do
    @artist.spotify_id = nil

    result = @artist.fetch_and_cache_top_tracks
    assert_equal [], result
  end

  test "fetch_and_cache_top_tracks handles API errors gracefully" do
    @artist.expects(:to_rspotify_artist).raises(StandardError.new("API Error"))

    result = @artist.fetch_and_cache_top_tracks
    assert_equal [], result
  end

  test "fetch_and_cache_top_tracks avoids cross-contamination between artists" do
    # This test ensures that when an album/track exists for another artist,
    # we create separate records for this artist
    other_artist = artists(:two)
    shared_album_spotify_id = "shared_album_123"

    # Create an album for the other artist
    other_album = Album.create!(
      spotify_id: shared_album_spotify_id,
      name: "Compilation Album",
      artist: other_artist
    )

    spotify_artist = mock_spotify_artist(id: @artist.spotify_id)
    spotify_track = mock_spotify_track(id: "featured_track_123", name: "Featured Song")
    spotify_album = mock_spotify_album(id: shared_album_spotify_id, name: "Compilation Album")
    spotify_track.stubs(:album).returns(spotify_album)

    @artist.expects(:to_rspotify_artist).returns(spotify_artist)
    spotify_artist.expects(:top_tracks).returns([ spotify_track ])

    # The method should create a new album record for this artist
    assert_difference "Album.count", 1 do
      @artist.fetch_and_cache_top_tracks(limit: 1)
    end

    # Verify we have separate albums for each artist
    assert_equal 2, Album.where(spotify_id: shared_album_spotify_id).count
  end
end
