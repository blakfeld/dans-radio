require "rest-client"

module Spotify
  class SyncPlaylistTracks < SpotifyService
    def self.call(playlist_name:, sync_full_artist_catalog: true, rate_limit_delay: 0.5, &block)
      new(
        playlist_name: playlist_name,
        sync_full_artist_catalog: sync_full_artist_catalog,
        rate_limit_delay: rate_limit_delay
      ).call(&block)
    end

    def initialize(playlist_name:, sync_full_artist_catalog: true, rate_limit_delay: 0.5)
      @playlist_name = playlist_name
      @sync_full_artist_catalog = sync_full_artist_catalog
      @rate_limit_delay = rate_limit_delay # Delay in seconds between API calls (default ~3 req/sec)
      @synced_tracks_count = 0
      @synced_albums_count = 0
      @synced_artists_count = 0
      @error_count = 0
      @errors = []
      @processed_artist_ids = Set.new
      @processed_album_ids = Set.new
      @artist_cache = {} # Cache RSpotify artist objects
      @albums_to_batch_fetch = [] # Accumulate albums for batch fetching
      @tracks_to_batch_save = [] # Accumulate tracks for batch saving
      @albums_to_batch_save = [] # Accumulate albums for batch saving
      @last_api_call = Time.current
      @api_call_count = 0
    end

    def call(&block)
      playlist = fetch_playlist
      return { success: false, error: "Playlist '#{@playlist_name}' not found" } unless playlist

      all_playlist_tracks = fetch_all_tracks(playlist)

      # First, sync the playlist tracks and collect unique artists
      yield("Syncing playlist tracks...", 0, 100) if block_given?
      unique_artists = sync_playlist_tracks_and_collect_artists(all_playlist_tracks, &block)

      # If full artist catalog sync is enabled, fetch and sync all albums/tracks for each artist
      if @sync_full_artist_catalog && unique_artists.any?
        yield("Syncing full artist catalogs...", 50, 100) if block_given?
        sync_full_artist_catalogs(unique_artists, &block)
      end

      {
        success: true,
        playlist_name: playlist.name,
        playlist_tracks_count: all_playlist_tracks.length,
        synced_tracks_count: @synced_tracks_count,
        synced_albums_count: @synced_albums_count,
        synced_artists_count: @synced_artists_count,
        unique_artists_count: unique_artists.size,
        error_count: @error_count,
        errors: @errors,
        stats: {
          artists: Artist.count,
          albums: Album.count,
          tracks: Track.count
        }
      }
    rescue => e
      {
        success: false,
        error: e.message,
        backtrace: Rails.env.development? ? e.backtrace.first(5) : nil
      }
    end

    private

    def fetch_playlist
      with_rate_limit_retry do
        Spotify::GetPlaylist.call(id: nil, name: @playlist_name)
      end
    end

    def fetch_all_tracks(playlist)
      all_tracks = []
      offset = 0
      limit = 100

      while offset < playlist.total
        tracks = with_rate_limit_retry do
          playlist.tracks(limit: limit, offset: offset)
        end
        all_tracks.concat(tracks) if tracks
        offset += limit
      end

      all_tracks
    end

    def sync_playlist_tracks_and_collect_artists(tracks, &block)
      unique_artists = Set.new

      tracks.each_with_index do |track, index|
        artist_record = sync_single_track(track, index, tracks.length, &block)
        unique_artists.add(artist_record) if artist_record
      end

      unique_artists.to_a.compact
    end

    def sync_full_artist_catalogs(artists, &block)
      total = artists.size

      # Pre-fetch all artist objects in parallel to minimize API calls
      yield("Pre-fetching artist data...", 50, 100) if block_given?
      prefetch_artist_objects(artists)

      artists.each_with_index do |artist_record, index|
        next if @processed_artist_ids.include?(artist_record.spotify_id)

        yield("Fetching albums for #{artist_record.name}...", 50 + (index * 50 / total), 100) if block_given?

        begin
          # Use cached artist object if available
          rspotify_artist = @artist_cache[artist_record.spotify_id] || with_rate_limit_retry do
            artist_record.to_rspotify_artist
          end
          next unless rspotify_artist

          # Fetch all albums for this artist (including singles, compilations, etc.)
          fetch_and_sync_artist_albums(rspotify_artist, artist_record, &block)

          @processed_artist_ids.add(artist_record.spotify_id)
          @synced_artists_count += 1
        rescue => e
          increment_error("Error syncing catalog for artist '#{artist_record.name}': #{e.message}")
        end
      end

      # Process any remaining batched albums
      process_batched_albums if @albums_to_batch_fetch.any?

      # Bulk save any remaining tracks and albums
      bulk_save_tracks if @tracks_to_batch_save.any?
      bulk_save_albums if @albums_to_batch_save.any?
    end

    def prefetch_artist_objects(artists)
      # RSpotify doesn't support batch fetching artists, but we can cache them
      # to avoid redundant calls when the same artist appears multiple times
      artists.each do |artist_record|
        next if @artist_cache[artist_record.spotify_id]

        begin
          @artist_cache[artist_record.spotify_id] = with_rate_limit_retry do
            RSpotify::Artist.find(artist_record.spotify_id)
          end
        rescue => e
          Rails.logger.warn "Failed to prefetch artist #{artist_record.spotify_id}: #{e.message}"
        end
      end
    end

    def fetch_and_sync_artist_albums(rspotify_artist, artist_record, &block)
      # Fetch albums in batches (Spotify API limits)
      limit = 50
      offset = 0
      all_albums = []

      # First, collect all albums for this artist
      loop do
        albums = with_rate_limit_retry do
          rspotify_artist.albums(limit: limit, offset: offset, album_type: "album,single,compilation")
        end
        break if albums.nil? || albums.empty?

        albums.each do |album|
          next if @processed_album_ids.include?(album.id)
          all_albums << { spotify_album: album, artist_record: artist_record }
        end

        offset += limit
        break if albums.size < limit
      end

      # Process albums in batches to fetch full album details
      all_albums.each_slice(20) do |album_batch| # Spotify allows up to 20 albums per request
        process_album_batch(album_batch, &block)
      end
    end

    def process_album_batch(album_batch, &block)
      album_ids = album_batch.map { |item| item[:spotify_album].id }

      begin
        # Fetch full album details in a single API call (up to 20 albums)
        full_albums = with_rate_limit_retry do
          RSpotify::Album.find(album_ids)
        end
        full_albums = [ full_albums ] unless full_albums.is_a?(Array) # Handle single album response

        full_albums.each_with_index do |full_album, index|
          artist_record = album_batch[index][:artist_record]

          # Sync the album
          album_record = sync_album_from_rspotify(full_album, artist_record)

          if album_record
            # Batch collect tracks instead of fetching immediately
            collect_album_tracks_for_batch(full_album, album_record)
            @synced_albums_count += 1
            @processed_album_ids.add(full_album.id)
          end
        end

        # Periodically save batched data to avoid memory issues
        if @tracks_to_batch_save.size > 100
          bulk_save_tracks
          @tracks_to_batch_save.clear
        end

        if @albums_to_batch_save.size > 50
          bulk_save_albums
          @albums_to_batch_save.clear
        end
      rescue => e
        increment_error("Error processing album batch: #{e.message}")
        # Fall back to individual processing if batch fails
        album_batch.each do |item|
          process_single_album(item[:spotify_album], item[:artist_record], &block)
        end
      end
    end

    def process_single_album(album, artist_record, &block)
      begin
        # Fallback method for processing a single album
        full_album = with_rate_limit_retry do
          RSpotify::Album.find(album.id)
        end
        album_record = sync_album_from_rspotify(full_album, artist_record)

        if album_record
          fetch_and_sync_album_tracks(full_album, album_record, &block)
          @synced_albums_count += 1
          @processed_album_ids.add(album.id)
        end
      rescue => e
        increment_error("Error syncing album '#{album.name}': #{e.message}")
      end
    end

    def collect_album_tracks_for_batch(rspotify_album, album_record)
      # Collect all tracks from the album for batch processing
      limit = 50
      offset = 0

      loop do
        tracks = rspotify_album.tracks(limit: limit, offset: offset)
        break if tracks.nil? || tracks.empty?

        tracks.each do |track|
          @tracks_to_batch_save << {
            spotify_track: track,
            album_record: album_record
          }
        end

        offset += limit
        break if tracks.size < limit
      end
    end

    def fetch_and_sync_album_tracks(rspotify_album, album_record, &block)
      # Fetch tracks in batches
      limit = 50
      offset = 0

      loop do
        tracks = with_rate_limit_retry do
          rspotify_album.tracks(limit: limit, offset: offset)
        end

        break if tracks.nil? || tracks.empty?

        tracks.each do |track|
          begin
            sync_track_from_rspotify(track, album_record)
            @synced_tracks_count += 1
          rescue => e
            increment_error("Error syncing track '#{track.name}': #{e.message}")
          end
        end

        offset += limit
        break if tracks.size < limit # No more tracks to fetch
      end
    end

    def sync_single_track(track, index, total, &block)
      return increment_error("Track is nil") if track.nil?

      # Call the progress block before processing
      yield(track, index, total) if block_given?

      artist_record = nil

      # Wrap the entire sync operation in retry logic
      with_rate_limit_retry do
        ActiveRecord::Base.transaction do
          artist_record = sync_artist(track)
          album_record = sync_album(track, artist_record)
          sync_track_record(track, album_record)
          @synced_tracks_count += 1 unless @sync_full_artist_catalog # Don't double-count if we're doing full sync
        end
      end

      artist_record
    rescue => e
      increment_error("Error syncing '#{track&.name}': #{e.message}")
      nil
    end

    def sync_artist(track)
      return nil unless track.artists.any?

      primary_artist = track.artists.first
      artist_record = Artist.find_or_initialize_by(spotify_id: primary_artist.id)

      # Some properties might trigger lazy loading and API calls
      # Access them carefully and handle potential errors
      artist_attributes = {
        name: primary_artist.name,
        uri: primary_artist.uri,
        href: primary_artist.href
      }

      # Images might trigger an API call - access carefully
      begin
        artist_attributes[:images] = primary_artist.images if primary_artist.respond_to?(:images)
      rescue => e
        Rails.logger.debug "Could not fetch artist images: #{e.message}"
      end

      artist_attributes[:images] ||= artist_record.images

      artist_record.assign_attributes(artist_attributes)
      artist_record.save! if artist_record.changed?
      artist_record
    end

    def sync_album(track, artist_record)
      return nil unless track.album

      album_record = Album.find_or_initialize_by(spotify_id: track.album.id)

      # Build attributes carefully as some might trigger API calls
      album_attributes = {
        name: track.album.name,
        artist_id: artist_record&.id,
        album_type: track.album.album_type,
        total_tracks: track.album.total_tracks,
        external_urls: track.album.external_urls,
        href: track.album.href,
        release_date: track.album.release_date,
        uri: track.album.uri
      }

      # Images might trigger an API call - access carefully
      begin
        album_attributes[:images] = track.album.images if track.album.respond_to?(:images)
      rescue => e
        Rails.logger.debug "Could not fetch album images: #{e.message}"
      end

      album_attributes[:images] ||= album_record.images

      album_record.assign_attributes(album_attributes)
      album_record.save! if album_record.changed?
      album_record
    end

    def sync_album_from_rspotify(rspotify_album, artist_record)
      return nil unless rspotify_album

      album_record = Album.find_or_initialize_by(spotify_id: rspotify_album.id)

      album_record.assign_attributes(
        name: rspotify_album.name,
        artist_id: artist_record&.id,
        album_type: rspotify_album.album_type,
        total_tracks: rspotify_album.total_tracks,
        external_urls: rspotify_album.external_urls.try(:to_h) || {},
        href: rspotify_album.href,
        images: rspotify_album.images.presence || album_record.images,
        release_date: rspotify_album.release_date,
        uri: rspotify_album.uri
      )

      # Add to batch save list instead of saving immediately
      if @albums_to_batch_save
        @albums_to_batch_save << album_record if album_record.changed?
      else
        album_record.save! if album_record.changed?
      end

      album_record
    end

    def sync_track_record(track, album_record)
      track_record = Track.find_or_initialize_by(spotify_id: track.id)

      track_record.assign_attributes(
        title: track.name,
        album_id: album_record&.id,
        duration_ms: track.duration_ms,
        explicit: track.explicit,
        href: track.href,
        is_playable: track.is_playable,
        preview_url: track.preview_url,
        track_number: track.track_number,
        uri: track.uri
      )

      track_record.save! if track_record.changed?
      track_record
    end

    def sync_track_from_rspotify(rspotify_track, album_record)
      track_record = Track.find_or_initialize_by(spotify_id: rspotify_track.id)

      track_record.assign_attributes(
        title: rspotify_track.name,
        album_id: album_record&.id,
        duration_ms: rspotify_track.duration_ms,
        explicit: rspotify_track.explicit,
        href: rspotify_track.href,
        is_playable: rspotify_track.try(:is_playable),
        preview_url: rspotify_track.preview_url,
        track_number: rspotify_track.track_number,
        uri: rspotify_track.uri
      )

      # Add to batch save list instead of saving immediately if in batch mode
      if @tracks_to_batch_save
        @tracks_to_batch_save << track_record if track_record.changed?
      else
        track_record.save! if track_record.changed?
      end

      track_record
    end

    def bulk_save_tracks
      return if @tracks_to_batch_save.empty?

      ActiveRecord::Base.transaction do
        # Process tracks that have actual track records
        tracks_to_save = @tracks_to_batch_save.select do |item|
          item.is_a?(Track) ? item : false
        end

        # Process track data that needs to be converted
        @tracks_to_batch_save.reject { |item| item.is_a?(Track) }.each do |item|
          if item.is_a?(Hash) && item[:spotify_track] && item[:album_record]
            track = sync_track_from_rspotify_batch(item[:spotify_track], item[:album_record])
            tracks_to_save << track if track&.changed?
          end
        end

        # Bulk save all tracks
        tracks_to_save.each(&:save!) if tracks_to_save.any?
        @synced_tracks_count += tracks_to_save.size
      end

      @tracks_to_batch_save.clear
    rescue => e
      increment_error("Error in bulk save tracks: #{e.message}")
      # Fall back to individual saves
      @tracks_to_batch_save.each do |item|
        begin
          if item.is_a?(Track)
            item.save! if item.changed?
          elsif item.is_a?(Hash)
            sync_track_from_rspotify(item[:spotify_track], item[:album_record])
          end
          @synced_tracks_count += 1
        rescue => save_error
          increment_error("Error saving track: #{save_error.message}")
        end
      end
    end

    def sync_track_from_rspotify_batch(rspotify_track, album_record)
      # Special version for batch processing that doesn't save immediately
      track_record = Track.find_or_initialize_by(spotify_id: rspotify_track.id)

      track_record.assign_attributes(
        title: rspotify_track.name,
        album_id: album_record&.id,
        duration_ms: rspotify_track.duration_ms,
        explicit: rspotify_track.explicit,
        href: rspotify_track.href,
        is_playable: rspotify_track.try(:is_playable),
        preview_url: rspotify_track.preview_url,
        track_number: rspotify_track.track_number,
        uri: rspotify_track.uri
      )

      track_record
    end

    def bulk_save_albums
      return if @albums_to_batch_save.empty?

      ActiveRecord::Base.transaction do
        @albums_to_batch_save.each(&:save!)
      end

      @albums_to_batch_save.clear
    rescue => e
      increment_error("Error in bulk save albums: #{e.message}")
      # Fall back to individual saves
      @albums_to_batch_save.each do |album|
        begin
          album.save! if album.changed?
        rescue => save_error
          increment_error("Error saving album: #{save_error.message}")
        end
      end
    end

    def process_batched_albums
      # Process any remaining albums that were queued for batch fetching
      @albums_to_batch_fetch.each_slice(20) do |batch|
        process_album_batch(batch)
      end
      @albums_to_batch_fetch.clear
    end

    def increment_error(message)
      @error_count += 1
      @errors << message
      nil
    end

    def enforce_rate_limit
      # Spotify's rate limit is approximately 180 requests per minute (3 per second)
      # We'll be conservative and aim for ~2.85 requests per second with default delay
      return unless @rate_limit_delay && @rate_limit_delay > 0

      time_since_last_call = Time.current - @last_api_call
      if time_since_last_call < @rate_limit_delay
        sleep_time = @rate_limit_delay - time_since_last_call
        sleep(sleep_time) if sleep_time > 0
      end

      @last_api_call = Time.current
      @api_call_count += 1

      # Log progress every 10 API calls in development
      if Rails.env.development? && @api_call_count % 10 == 0
        Rails.logger.debug "[Spotify Sync] #{@api_call_count} API calls made, rate limited to #{(1.0 / @rate_limit_delay).round(2)} req/sec"
      end
    end

      def handle_rate_limit_error(error, &block)
        # Extract retry-after header if available
        # Spotify sends this as seconds to wait
        retry_after = nil

        # Handle different error types
        if error.respond_to?(:response) && error.response
          if error.response.respond_to?(:headers)
            retry_after = error.response.headers[:retry_after]&.to_i ||
                        error.response.headers["retry-after"]&.to_i ||
                        error.response.headers["Retry-After"]&.to_i
          elsif error.response.respond_to?(:[])
            retry_after = error.response["Retry-After"]&.to_i ||
                        error.response["retry-after"]&.to_i
          end
        end

        retry_after ||= 30 # Default to 30 seconds if header not found

        Rails.logger.warn "[Spotify Sync] Rate limited! Waiting #{retry_after} seconds before retrying..."
        Rails.logger.warn "[Spotify Sync] Error class: #{error.class.name}"
        Rails.logger.warn "[Spotify Sync] Error message: #{error.message}" if error.respond_to?(:message)

        # Log response details for debugging
        if error.respond_to?(:response) && error.response
          Rails.logger.warn "[Spotify Sync] Response code: #{error.response.code if error.response.respond_to?(:code)}"
          Rails.logger.warn "[Spotify Sync] Response headers: #{error.response.headers.inspect if error.response.respond_to?(:headers)}"
        end

        # Show progress to user
        yield("Rate limited by Spotify. Waiting #{retry_after} seconds...", @api_call_count, @api_call_count) if block_given?

        sleep(retry_after)
        @last_api_call = Time.current # Reset the timer after waiting
      end

      # Wrapper method to execute API calls with rate limiting and retry logic
      def with_rate_limit_retry(max_retries: 3, &block)
        retries = 0
        begin
          enforce_rate_limit
          yield
        rescue RestClient::TooManyRequests, RestClient::RequestFailed => e
          # Check if it's a 429 error
          if e.respond_to?(:response) && e.response && (e.response.code == 429 || e.message&.include?("429"))
            retries += 1
            if retries <= max_retries
              Rails.logger.info "[Spotify Sync] Rate limited (attempt #{retries}/#{max_retries})"
              handle_rate_limit_error(e, &block)
              retry
            else
              Rails.logger.error "[Spotify Sync] Max retries (#{max_retries}) exceeded for rate limiting"
              raise
            end
          else
            raise # Re-raise non-429 errors
          end
        rescue StandardError => e
          # Check if it's a rate limit error in disguise
          if e.message&.include?("429") || e.message&.downcase&.include?("rate limit") || e.message&.downcase&.include?("too many requests")
            retries += 1
            if retries <= max_retries
              Rails.logger.info "[Spotify Sync] Rate limited via error message (attempt #{retries}/#{max_retries}): #{e.message}"
              handle_rate_limit_error(e, &block)
              retry
            else
              Rails.logger.error "[Spotify Sync] Max retries (#{max_retries}) exceeded for rate limiting"
              raise
            end
          else
            raise # Re-raise non-rate-limit errors
          end
        end
      end
  end
end
