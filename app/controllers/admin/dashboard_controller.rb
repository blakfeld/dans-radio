module Admin
  class DashboardController < ::ApplicationController
    before_action :require_admin
    def index
      @total_artists = Artist.count
      @total_tracks = Track.count
      @total_albums = Album.count
      @total_requests = SongRequest.count
      @pending_requests = SongRequest.pending.count
      @recent_requests = SongRequest.includes(:track)
                                   .order(created_at: :desc)
                                   .limit(10)
      @currently_playing = SongRequest.playing.first

      # User statistics
      @total_users = User.count
      @admin_users = User.admins.count
      @locked_users = User.locked.count
    end
  end
end
