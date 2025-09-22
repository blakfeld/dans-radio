class SyncSpotifyPlaylistJob < ApplicationJob
  queue_as :default

  # Default playlist name if none provided
  DEFAULT_PLAYLIST = "Dan's Radio".freeze

  def perform(playlist_name = nil, options = {})
    playlist_name ||= DEFAULT_PLAYLIST
    log_progress = options.fetch(:log_progress, true)
    sync_full_artist_catalog = options.fetch(:sync_full_artist_catalog, true)
    rate_limit_delay = options.fetch(:rate_limit_delay, 0.5) # Default to 2 requests per second

    Rails.logger.info "Starting Spotify playlist sync for: #{playlist_name}"
    Rails.logger.info "Sync full artist catalogs: #{sync_full_artist_catalog}" if sync_full_artist_catalog
    Rails.logger.info "Rate limit delay: #{rate_limit_delay}s (#{(1.0 / rate_limit_delay).round(2)} req/sec)" if rate_limit_delay > 0

    begin
      # Use the service object to sync the playlist
      result = Spotify::SyncPlaylistTracks.call(
        playlist_name: playlist_name,
        sync_full_artist_catalog: sync_full_artist_catalog,
        rate_limit_delay: rate_limit_delay
      ) do |info, index, total|
        # Log progress every 10 items if enabled
        if log_progress && info.respond_to?(:name) && (index + 1) % 10 == 0
          Rails.logger.info "[SyncSpotifyPlaylist] Progress: #{index + 1}/#{total} tracks processed"
        elsif log_progress && info.is_a?(String)
          Rails.logger.info "[SyncSpotifyPlaylist] #{info}"
        end
      end

      if result[:success]
        Rails.logger.info build_success_message(result, playlist_name)

        # Log errors if any occurred
        if result[:error_count] > 0 && result[:errors].any?
          Rails.logger.warn "Sync completed with #{result[:error_count]} errors:"
          result[:errors].first(10).each do |error|
            Rails.logger.warn "  - #{error}"
          end
        end
      else
        Rails.logger.error "Failed to sync playlist '#{playlist_name}': #{result[:error]}"
        Rails.logger.error result[:backtrace].join("\n") if result[:backtrace]

        # Re-raise to trigger job retry mechanism if configured
        raise "Playlist sync failed: #{result[:error]}"
      end

      result
    rescue StandardError => e
      Rails.logger.error "Unexpected error syncing playlist '#{playlist_name}': #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      # Re-raise to use Active Job's retry mechanism
      raise
    end
  end

  private

  def build_success_message(result, playlist_name)
    message = []
    message << "Successfully synced playlist '#{playlist_name}'"
    message << "Playlist tracks: #{result[:playlist_tracks_count]}"
    message << "Unique artists: #{result[:unique_artists_count]}"
    message << "Tracks synced: #{result[:synced_tracks_count]}"
    message << "Albums synced: #{result[:synced_albums_count]}"
    message << "Errors: #{result[:error_count]}"
    message << "Database stats - Artists: #{result[:stats][:artists]}, Albums: #{result[:stats][:albums]}, Tracks: #{result[:stats][:tracks]}"
    message.join(" | ")
  end
end
