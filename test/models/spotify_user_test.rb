require "test_helper"

class SpotifyUserTest < ActiveSupport::TestCase
  setup do
    @spotify_user = spotify_users(:one)
    @spotify_user.update!(
      username: "test_user",
      email: "test@example.com",
      token: "test_token_123",
      refresh_token: "refresh_token_456",
      expires_at: 1.hour.from_now,
      spotify_hash: {
        "credentials" => {
          "token" => "test_token_123",
          "refresh_token" => "refresh_token_456",
          "expires_at" => 1.hour.from_now.to_i
        },
        "info" => {
          "id" => "test_user",
          "email" => "test@example.com"
        }
      }
    )
  end

  # Serialization
  test "serializes spotify_hash as JSON" do
    hash = { "test" => "data", "nested" => { "key" => "value" } }
    @spotify_user.spotify_hash = hash
    @spotify_user.save!
    @spotify_user.reload

    assert_equal Hash, @spotify_user.spotify_hash.class
    assert_equal "data", @spotify_user.spotify_hash["test"]
    assert_equal "value", @spotify_user.spotify_hash["nested"]["key"]
  end

  # Class methods
  test "from_omniauth creates new user from auth hash" do
    auth = OpenStruct.new(
      info: OpenStruct.new(
        id: "new_user_123",
        email: "new@example.com"
      ),
      credentials: OpenStruct.new(
        token: "new_token",
        refresh_token: "new_refresh",
        expires_at: 2.hours.from_now.to_i
      )
    )
    auth.define_singleton_method(:to_hash) { { "test" => "hash" } }

    user = SpotifyUser.from_omniauth(auth)

    assert user.persisted?
    assert_equal "new_user_123", user.username
    assert_equal "new@example.com", user.email
    assert_equal "new_token", user.token
    assert_equal "new_refresh", user.refresh_token
    assert_in_delta Time.at(auth.credentials.expires_at), user.expires_at, 1
    assert_equal({ "test" => "hash" }, user.spotify_hash)
  end

  test "from_omniauth updates existing user" do
    auth = OpenStruct.new(
      info: OpenStruct.new(
        id: @spotify_user.username,
        email: "updated@example.com"
      ),
      credentials: OpenStruct.new(
        token: "updated_token",
        refresh_token: "updated_refresh",
        expires_at: 3.hours.from_now.to_i
      )
    )
    auth.define_singleton_method(:to_hash) { { "updated" => "hash" } }

    user = SpotifyUser.from_omniauth(auth)

    assert_equal @spotify_user.id, user.id
    assert_equal "updated@example.com", user.email
    assert_equal "updated_token", user.token
    assert_equal "updated_refresh", user.refresh_token
  end

  # Instance methods
  test "to_rspotify_user creates RSpotify user from stored hash" do
    mock_user = mock_spotify_user
    RSpotify::User.expects(:new).with(@spotify_user.spotify_hash).returns(mock_user)

    result = @spotify_user.to_rspotify_user
    assert_equal mock_user, result
  end

  test "to_rspotify_user creates user from fallback data when spotify_hash is nil" do
    @spotify_user.spotify_hash = nil
    mock_user = mock_spotify_user

    RSpotify::User.expects(:new) do |hash|
      assert_equal @spotify_user.token, hash["credentials"]["token"]
      assert_equal @spotify_user.refresh_token, hash["credentials"]["refresh_token"]
      assert_equal @spotify_user.username, hash["info"]["id"]
      assert_equal @spotify_user.email, hash["info"]["email"]
      mock_user
    end

    result = @spotify_user.to_rspotify_user
    assert_equal mock_user, result
  end

  # Token expiration tests
  test "token_expired? returns true when token is expired" do
    @spotify_user.expires_at = 1.minute.ago
    assert @spotify_user.token_expired?

    @spotify_user.expires_at = 1.minute.from_now
    assert_not @spotify_user.token_expired?
  end

  test "token_expired? returns false when expires_at is nil" do
    @spotify_user.expires_at = nil
    assert_not @spotify_user.token_expired?
  end

  test "token_expiring_soon? returns true when token expires within 5 minutes" do
    @spotify_user.expires_at = 4.minutes.from_now
    assert @spotify_user.token_expiring_soon?

    @spotify_user.expires_at = 6.minutes.from_now
    assert_not @spotify_user.token_expiring_soon?

    @spotify_user.expires_at = 1.minute.ago
    assert @spotify_user.token_expiring_soon?
  end

  test "token_expiring_soon? returns false when expires_at is nil" do
    @spotify_user.expires_at = nil
    assert_not @spotify_user.token_expiring_soon?
  end

  # Token refresh tests
  test "refresh_access_token! successfully refreshes token" do
    mock_response = {
      "access_token" => "new_access_token",
      "expires_in" => 3600
    }.to_json

    stub_request(:post, "https://accounts.spotify.com/api/token")
      .with(
        body: { "grant_type" => "refresh_token", "refresh_token" => @spotify_user.refresh_token },
        headers: { "Authorization" => /Basic .+/ }
      )
      .to_return(status: 200, body: mock_response, headers: { "Content-Type" => "application/json" })

    Rails.application.credentials.stub(:spotify, { client_id: "test_id", client_secret: "test_secret" }) do
      result = @spotify_user.refresh_access_token!

      assert result
      assert_equal "new_access_token", @spotify_user.token
      assert_in_delta Time.current + 3600.seconds, @spotify_user.expires_at, 2
    end
  end

  test "refresh_access_token! returns false when refresh_token is missing" do
    @spotify_user.refresh_token = nil
    result = @spotify_user.refresh_access_token!
    assert_equal false, result
  end

  test "refresh_access_token! handles API errors gracefully" do
    stub_request(:post, "https://accounts.spotify.com/api/token")
      .to_return(status: 401, body: '{"error": "invalid_grant"}')

    Rails.application.credentials.stub(:spotify, { client_id: "test_id", client_secret: "test_secret" }) do
      result = @spotify_user.refresh_access_token!
      assert_equal false, result
    end
  end

  test "refresh_access_token! updates spotify_hash when present" do
    @spotify_user.spotify_hash = {
      "credentials" => {
        "token" => "old_token",
        "expires_at" => 1.hour.ago.to_i
      }
    }

    mock_response = {
      "access_token" => "refreshed_token",
      "expires_in" => 3600
    }.to_json

    stub_request(:post, "https://accounts.spotify.com/api/token")
      .to_return(status: 200, body: mock_response)

    Rails.application.credentials.stub(:spotify, { client_id: "test_id", client_secret: "test_secret" }) do
      @spotify_user.refresh_access_token!

      assert_equal "refreshed_token", @spotify_user.spotify_hash["credentials"]["token"]
      assert @spotify_user.spotify_hash["credentials"]["expires_at"] > Time.current.to_i
    end
  end

  # Integration methods
  test "to_rspotify_user_with_refresh refreshes token when expiring soon" do
    @spotify_user.expires_at = 4.minutes.from_now

    @spotify_user.expects(:refresh_access_token!).returns(true)
    @spotify_user.expects(:to_rspotify_user)

    @spotify_user.to_rspotify_user_with_refresh
  end

  test "to_rspotify_user_with_refresh doesn't refresh when token is fresh" do
    @spotify_user.expires_at = 1.hour.from_now

    @spotify_user.expects(:refresh_access_token!).never
    @spotify_user.expects(:to_rspotify_user)

    @spotify_user.to_rspotify_user_with_refresh
  end
end
