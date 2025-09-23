require "test_helper"

class NowPlayingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @artist = artists(:one)
    @album = albums(:one)
    @track = tracks(:one)

    # Create some test artists for browsing
    @popular_artist = Artist.create!(
      spotify_id: "popular_123",
      name: "Popular Artist",
      popularity: 85
    )
    @random_artist = Artist.create!(
      spotify_id: "random_456",
      name: "Random Artist",
      popularity: 45
    )

    # Create albums for the artists
    Album.create!(
      spotify_id: "pop_album_123",
      name: "Popular Album",
      artist: @popular_artist
    )
    Album.create!(
      spotify_id: "random_album_456",
      name: "Random Album",
      artist: @random_artist
    )
  end

  # Index action tests
  test "should get index" do
    mock_spotify_response = {
      track: mock_spotify_track(id: @track.spotify_id),
      progress_ms: 60000,
      is_playing: true
    }

    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(mock_spotify_response)

    get now_playing_url
    assert_response :success
    assert_not_nil assigns(:currently_playing)
    assert_not_nil assigns(:queue_count)
    assert_not_nil assigns(:artists)
  end

  test "displays currently playing track" do
    # Create a playing song request
    song_request = SongRequest.create!(
      request_queue: RequestQueue.get,
      track: @track,
      status: "playing",
      position: 0
    )

    mock_spotify_response = {
      track: mock_spotify_track(id: @track.spotify_id),
      progress_ms: 30000,
      is_playing: true
    }

    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(mock_spotify_response)

    get now_playing_url
    assert_response :success

    currently_playing = assigns(:currently_playing)
    assert_equal @track, currently_playing[:track]
    assert_equal 30000, currently_playing[:progress_ms]
    assert_equal true, currently_playing[:is_playing]
  end

  test "calculates queue duration" do
    queue = RequestQueue.get
    # Create active requests
    queue.song_requests.create!(
      track: @track,
      status: "queued",
      position: 0
    )
    queue.song_requests.create!(
      track: tracks(:two),
      status: "pending",
      position: 1
    )

    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url
    assert_response :success

    assert_not_nil assigns(:queue_duration_ms)
    assert assigns(:queue_duration_ms) > 0
    assert_not_nil assigns(:queue_duration_mins)
  end

  # Search functionality
  test "searches artists by name" do
    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url, params: { q: "Popular" }
    assert_response :success

    artists = assigns(:artists)
    assert_includes artists.map(&:name), "Popular Artist"
    assert_not_includes artists.map(&:name), "Random Artist"
    assert_equal false, assigns(:discovery_mode)
  end

  test "shows discovery artists when no search" do
    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url
    assert_response :success

    assert_equal true, assigns(:discovery_mode)
    assert_not_nil assigns(:total_artists)
    artists = assigns(:artists)
    assert artists.any?
  end

  test "case-insensitive search" do
    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url, params: { q: "popular" }
    assert_response :success

    artists = assigns(:artists)
    assert_includes artists.map(&:name), "Popular Artist"
  end

  # Turbo Frame support
  test "renders partial for turbo frame request" do
    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url, headers: { "Turbo-Frame" => "artist_results" }
    assert_response :success
    assert_match /artist_results/, @response.body
  end

  # JSON format
  test "returns json response" do
    mock_spotify_response = {
      track: mock_spotify_track(
        id: @track.spotify_id,
        name: @track.title,
        duration_ms: 180000
      ),
      progress_ms: 60000,
      is_playing: true
    }

    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(mock_spotify_response)

    get now_playing_url, as: :json
    assert_response :success

    json_response = JSON.parse(@response.body)
    assert_not_nil json_response["currently_playing"]
    assert_not_nil json_response["queue_count"]
  end

  # Cooldown functionality
  test "checks request cooldown" do
    # Set last request time in session
    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url, params: {}, session: { last_request_time: 1.minute.ago.to_s }
    assert_response :success

    assert_equal false, assigns(:can_request)
    assert assigns(:cooldown_remaining) > 0
  end

  test "no cooldown when sufficient time passed" do
    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url, params: {}, session: { last_request_time: 10.minutes.ago.to_s }
    assert_response :success

    assert_equal true, assigns(:can_request)
    assert_nil assigns(:cooldown_remaining)
  end

  # Error handling
  test "handles spotify api errors gracefully" do
    Spotify::GetCurrentlyPlaying.any_instance.expects(:call)
      .raises(StandardError.new("API Error"))

    get now_playing_url
    assert_response :success
    assert_nil assigns(:currently_playing)
  end

  test "falls back to song request when spotify unavailable" do
    # Create a playing request
    playing_request = SongRequest.create!(
      request_queue: RequestQueue.get,
      track: @track,
      status: "playing",
      position: 0
    )

    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url
    assert_response :success

    currently_playing = assigns(:currently_playing)
    assert_not_nil currently_playing
    assert_equal @track, currently_playing[:track]
    assert_equal false, currently_playing[:is_playing]
  end

  # Discovery mode
  test "shows mix of popular and random artists in discovery" do
    # Create more artists with varying popularity
    10.times do |i|
      artist = Artist.create!(
        spotify_id: "artist_#{i}",
        name: "Artist #{i}",
        popularity: rand(20..90)
      )
      Album.create!(
        spotify_id: "album_#{i}",
        name: "Album #{i}",
        artist: artist
      )
    end

    Spotify::GetCurrentlyPlaying.any_instance.expects(:call).returns(nil)

    get now_playing_url
    assert_response :success

    artists = assigns(:artists)
    assert artists.size <= 20
    assert artists.any? { |a| a.popularity.to_i > 30 } if artists.any?(&:popularity)
  end
end
