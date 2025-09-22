class SyncMultiplePlaylistsJob < ApplicationJob
  queue_as :low_priority

  def perform(playlist_names = [], options = {})
    # Use default playlists if none provided
    playlist_names = default_playlists if playlist_names.empty?
    sync_full_artist_catalog = options.fetch(:sync_full_artist_catalog, true)
    rate_limit_delay = options.fetch(:rate_limit_delay, 0.5)

    Rails.logger.info "Starting sync for #{playlist_names.length} playlists"
    Rails.logger.info "Sync full artist catalogs: #{sync_full_artist_catalog}" if sync_full_artist_catalog
    Rails.logger.info "Rate limit delay: #{rate_limit_delay}s" if rate_limit_delay > 0

    results = {
      successful: [],
      failed: [],
      total_tracks_synced: 0,
      total_errors: 0
    }

    playlist_names.each do |playlist_name|
      Rails.logger.info "Syncing playlist: #{playlist_name}"

      begin
        result = Spotify::SyncPlaylistTracks.call(
          playlist_name: playlist_name,
          sync_full_artist_catalog: sync_full_artist_catalog,
          rate_limit_delay: rate_limit_delay
        )

        if result[:success]
          results[:successful] << playlist_name
          results[:total_tracks_synced] += result[:synced_tracks_count]
          results[:total_errors] += result[:error_count]

          Rails.logger.info "✓ Successfully synced '#{playlist_name}': #{result[:synced_tracks_count]} tracks, #{result[:synced_albums_count]} albums"
        else
          results[:failed] << { name: playlist_name, error: result[:error] }
          Rails.logger.error "✗ Failed to sync '#{playlist_name}': #{result[:error]}"
        end
      rescue StandardError => e
        results[:failed] << { name: playlist_name, error: e.message }
        Rails.logger.error "✗ Unexpected error syncing '#{playlist_name}': #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end

      # Add a small delay between playlists to avoid rate limiting
      sleep(2) if playlist_names.length > 1
    end

    log_final_summary(results, playlist_names.length)
    results
  end

  private

  def default_playlists
    # You can configure these in Rails configuration or environment variables
    # For now, just return a default set
    [ "Dan's Radio" ]
  end

  def log_final_summary(results, total_count)
    Rails.logger.info "=" * 50
    Rails.logger.info "Playlist Sync Summary:"
    Rails.logger.info "  Total playlists: #{total_count}"
    Rails.logger.info "  Successful: #{results[:successful].length}"
    Rails.logger.info "  Failed: #{results[:failed].length}"
    Rails.logger.info "  Total tracks synced: #{results[:total_tracks_synced]}"
    Rails.logger.info "  Total errors: #{results[:total_errors]}"

    if results[:failed].any?
      Rails.logger.warn "Failed playlists:"
      results[:failed].each do |failure|
        Rails.logger.warn "  - #{failure[:name]}: #{failure[:error]}"
      end
    end

    Rails.logger.info "=" * 50
  end
end
