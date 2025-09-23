require "test_helper"

class AlbumTest < ActiveSupport::TestCase
  setup do
    @artist = artists(:one)
    @album = albums(:one)
  end

  # Associations
  test "belongs to artist" do
    assert_respond_to @album, :artist
    assert_instance_of Artist, @album.artist
  end

  test "has many tracks" do
    assert_respond_to @album, :tracks
    assert_kind_of ActiveRecord::Associations::CollectionProxy, @album.tracks
  end

  # Serialization
  test "serializes images as JSON" do
    @album.images = [ { url: "http://example.com/image.jpg", height: 300, width: 300 } ]
    @album.save!
    @album.reload
    assert_equal Array, @album.images.class
    assert_equal "http://example.com/image.jpg", @album.images.first["url"]
  end

  test "serializes external_urls as JSON" do
    @album.external_urls = { spotify: "http://spotify.com/album/123" }
    @album.save!
    @album.reload
    assert_equal Hash, @album.external_urls.class
    assert_equal "http://spotify.com/album/123", @album.external_urls["spotify"]
  end

  # Instance methods
  test "to_rspotify_album returns RSpotify album object" do
    mock_album = mock_spotify_album(id: @album.spotify_id)
    RSpotify::Album.expects(:find).with(@album.spotify_id).returns(mock_album)

    rspotify_album = @album.to_rspotify_album
    assert_equal mock_album, rspotify_album
  end

  # Class methods
  test "create_from_spotify creates album with all attributes" do
    artist = artists(:one)
    spotify_artist = mock_spotify_artist(id: artist.spotify_id)
    spotify_album = mock_spotify_album(
      id: "new_album_123",
      name: "New Album",
      album_type: "single",
      total_tracks: 3,
      release_date: "2024-01-15",
      uri: "spotify:album:new_album_123"
    )
    spotify_album.stubs(:artists).returns([ spotify_artist ])

    Artist.expects(:find_by_spotify_id).with(spotify_artist.id).returns(artist)

    album = Album.create_from_spotify(spotify_album)

    assert_not_nil album
    assert album.persisted?
    assert_equal "new_album_123", album.spotify_id
    assert_equal "New Album", album.name
    assert_equal artist.id, album.artist_id
    assert_equal "single", album.album_type
    assert_equal 3, album.total_tracks
  end

  test "create_from_spotify returns nil for nil input" do
    assert_nil Album.create_from_spotify(nil)
  end

  test "create_from_spotify handles missing artist" do
    spotify_album = mock_spotify_album(artists: false)

    album = Album.create_from_spotify(spotify_album)

    assert_not_nil album
    assert_nil album.artist_id
  end

  test "create_from_spotify handles validation errors" do
    spotify_album = mock_spotify_album(id: nil)

    album = Album.create_from_spotify(spotify_album)
    assert_nil album
  end

  test "update_from_spotify updates album attributes" do
    updated_spotify_album = mock_spotify_album(
      id: @album.spotify_id,
      name: "Updated Album Name",
      album_type: "compilation",
      total_tracks: 15
    )
    spotify_artist = mock_spotify_artist(id: @artist.spotify_id)
    updated_spotify_album.stubs(:artists).returns([ spotify_artist ])

    @album.expects(:to_rspotify_album).returns(updated_spotify_album)
    Artist.expects(:find_by_spotify_id).with(spotify_artist.id).returns(@artist)

    result = @album.update_from_spotify

    assert result
    @album.reload
    assert_equal "Updated Album Name", @album.name
    assert_equal "compilation", @album.album_type
    assert_equal 15, @album.total_tracks
  end

  test "update_from_spotify returns false when Spotify album not found" do
    @album.expects(:to_rspotify_album).returns(nil)

    result = @album.update_from_spotify
    assert_equal false, result
  end

  test "update_from_spotify handles errors gracefully" do
    @album.expects(:to_rspotify_album).raises(StandardError.new("API Error"))

    result = @album.update_from_spotify
    assert_equal false, result
  end
end
