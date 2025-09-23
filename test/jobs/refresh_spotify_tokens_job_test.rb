require "test_helper"

class RefreshSpotifyTokensJobTest < ActiveJob::TestCase
  setup do
    @expired_user = SpotifyUser.create!(
      username: "expired_user",
      email: "expired@example.com",
      token: "old_token",
      refresh_token: "refresh_token_expired",
      expires_at: 1.hour.ago
    )

    @expiring_soon_user = SpotifyUser.create!(
      username: "expiring_user",
      email: "expiring@example.com",
      token: "soon_expired",
      refresh_token: "refresh_token_expiring",
      expires_at: 3.minutes.from_now
    )

    @fresh_user = SpotifyUser.create!(
      username: "fresh_user",
      email: "fresh@example.com",
      token: "fresh_token",
      refresh_token: "refresh_token_fresh",
      expires_at: 2.hours.from_now
    )

    @no_refresh_user = SpotifyUser.create!(
      username: "no_refresh",
      email: "norefresh@example.com",
      token: "token",
      refresh_token: nil,
      expires_at: 1.hour.ago
    )
  end

  test "refreshes tokens for expired users" do
    @expired_user.expects(:refresh_access_token!).returns(true)
    @expiring_soon_user.expects(:refresh_access_token!).returns(true)
    @fresh_user.expects(:refresh_access_token!).never
    @no_refresh_user.expects(:refresh_access_token!).never

    perform_enqueued_jobs do
      RefreshSpotifyTokensJob.perform_later
    end
  end

  test "handles refresh failures gracefully" do
    @expired_user.expects(:refresh_access_token!).returns(false)
    @expiring_soon_user.expects(:refresh_access_token!).returns(true)

    # Should not raise error
    assert_nothing_raised do
      perform_enqueued_jobs do
        RefreshSpotifyTokensJob.perform_later
      end
    end
  end

  test "handles exceptions during refresh" do
    @expired_user.expects(:refresh_access_token!).raises(StandardError.new("API Error"))
    @expiring_soon_user.expects(:refresh_access_token!).returns(true)

    # Should not raise error, continues with other users
    assert_nothing_raised do
      perform_enqueued_jobs do
        RefreshSpotifyTokensJob.perform_later
      end
    end
  end

  test "skips users without refresh tokens" do
    @no_refresh_user.expects(:refresh_access_token!).never

    perform_enqueued_jobs do
      RefreshSpotifyTokensJob.perform_later
    end
  end

  test "skips users with fresh tokens" do
    @fresh_user.expects(:refresh_access_token!).never

    perform_enqueued_jobs do
      RefreshSpotifyTokensJob.perform_later
    end
  end

  test "refreshes multiple users in one job run" do
    # Create additional expired users
    additional_expired = SpotifyUser.create!(
      username: "another_expired",
      email: "another@example.com",
      token: "another_old",
      refresh_token: "another_refresh",
      expires_at: 2.hours.ago
    )

    @expired_user.expects(:refresh_access_token!).returns(true)
    @expiring_soon_user.expects(:refresh_access_token!).returns(true)
    additional_expired.expects(:refresh_access_token!).returns(true)

    perform_enqueued_jobs do
      RefreshSpotifyTokensJob.perform_later
    end
  end

  test "logs appropriate messages" do
    @expired_user.stubs(:refresh_access_token!).returns(true)
    @expiring_soon_user.stubs(:refresh_access_token!).returns(false)

    Rails.logger.expects(:info).with(/Starting Spotify token refresh job/)
    Rails.logger.expects(:info).with(/Found 2 users needing token refresh/)
    Rails.logger.expects(:info).with(/Successfully refreshed token for user: expired_user/)
    Rails.logger.expects(:error).with(/Failed to refresh token for user: expiring_user/)
    Rails.logger.expects(:info).with(/Completed Spotify token refresh job/)

    perform_enqueued_jobs do
      RefreshSpotifyTokensJob.perform_later
    end
  end
end

