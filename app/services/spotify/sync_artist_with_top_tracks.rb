module Spotify
  class SyncArtistWithTopTracks < SpotifyService
    attr_reader :artist_name, :spotify_artist_id, :fetch_top_tracks, :country

    def initialize(artist_name: nil, spotify_artist_id: nil, fetch_top_tracks: true, country: "US", rate_limit_delay: 0.35)
      @artist_name = artist_name
      @spotify_artist_id = spotify_artist_id
      @fetch_top_tracks = fetch_top_tracks
      @country = country
      @rate_limit_delay = rate_limit_delay # ~2.85 requests per second to stay under Spotify's 180/min limit
      @last_api_call = Time.current
      @api_call_count = 0

      # Batch processing collections
      @albums_to_batch_fetch = []
      @tracks_to_batch_save = []
      @albums_to_batch_save = []

      # Caching to avoid redundant calls
      @artist_cache = {}
      @album_cache = {}

      unless artist_name.present? || spotify_artist_id.present?
        raise ArgumentError, "Either artist_name or spotify_artist_id must be provided"
      end
    end

    def call
      # Find or fetch the Spotify artist
      spotify_artist = find_spotify_artist
      return nil unless spotify_artist

      # Cache the artist object for reuse
      @artist_cache[spotify_artist.id] = spotify_artist

      # Create or update the artist in our database
      artist = sync_artist(spotify_artist)
      return nil unless artist

      # Process albums and tracks together to maximize data utilization
      if artist
        # Fetch all albums and their tracks in an optimized manner
        sync_albums_and_tracks(artist, spotify_artist)

        # If we need top tracks and didn't already get them from album tracks
        if fetch_top_tracks && !already_have_top_tracks?(artist)
          sync_top_tracks(artist, spotify_artist)
        end
      end

      artist
    end

    private

    def find_spotify_artist
      with_rate_limit do
        if spotify_artist_id.present?
          # When fetching by ID, we get the full artist object including top tracks capability
          artist = RSpotify::Artist.find(spotify_artist_id)

          # If we have the artist, we can pre-cache some data
          if artist
            # The artist object already contains genres, popularity, images, etc.
            # No need for additional API calls for basic info
            Rails.logger.info "[Spotify Sync] Found artist '#{artist.name}' with #{artist.genres&.size || 0} genres"
          end

          artist
        elsif artist_name.present?
          # Search returns limited data, but we can still use it
          results = RSpotify::Artist.search(artist_name, limit: 1)
          artist = results.first

          if artist
            # For searched artists, we might want to fetch full details
            # But only if we'll need them later
            if fetch_top_tracks || need_full_artist_details?
              artist = RSpotify::Artist.find(artist.id)
            end
          end

          artist
        end
      end
    rescue => e
      Rails.logger.error "Error finding Spotify artist: #{e.message}"
      nil
    end

    def sync_artist(spotify_artist)
      artist = Artist.find_or_initialize_by(spotify_id: spotify_artist.id)

      # Extract all available data from the spotify_artist object
      artist.update!(
        name: spotify_artist.name,
        images: spotify_artist.images,
        uri: spotify_artist.uri,
        href: spotify_artist.href,
        genres: spotify_artist.genres,
        popularity: spotify_artist.popularity,
        # Store additional metadata that might be useful
        external_urls: spotify_artist.try(:external_urls),
        followers: spotify_artist.try(:followers).try(:[], "total")
      )

      artist
    rescue => e
      Rails.logger.error "Error syncing artist: #{e.message}"
      nil
    end

    def sync_albums_and_tracks(artist, spotify_artist)
      all_albums = []

      # Fetch all albums in batches (Spotify limits to 50 per request)
      with_rate_limit do
        limit = 50
        offset = 0

        loop do
          albums = spotify_artist.albums(
            limit: limit,
            offset: offset,
            album_type: "album,single",
            country: country
          )

          break if albums.nil? || albums.empty?

          all_albums.concat(albums)
          offset += limit
          break if albums.size < limit
        end
      end

      Rails.logger.info "[Spotify Sync] Found #{all_albums.size} albums for #{artist.name}"

      # Process albums in batches of 20 (Spotify's limit for batch album fetch)
      all_albums.each_slice(20) do |album_batch|
        process_album_batch(artist, album_batch)
      end

      # Save any remaining batched data
      bulk_save_albums
      bulk_save_tracks
    rescue => e
      Rails.logger.error "Error syncing albums for artist #{artist.name}: #{e.message}"
    end

    def process_album_batch(artist, album_batch)
      album_ids = album_batch.map(&:id)

      # Fetch full album details in a single API call
      full_albums = with_rate_limit do
        albums = RSpotify::Album.find(album_ids)
        # Ensure it's always an array
        albums.is_a?(Array) ? albums : [albums]
      end

      full_albums.each do |spotify_album|
        # Cache the album for potential reuse
        @album_cache[spotify_album.id] = spotify_album

        # Prepare album for batch saving
        album_record = prepare_album_for_save(artist, spotify_album)

        # Extract tracks from the album (they come with the full album fetch!)
        # This is KEY - we get tracks "for free" with the album fetch
        if spotify_album.tracks && spotify_album.tracks.any?
          process_album_tracks(album_record, spotify_album.tracks)
        else
          # If tracks weren't included, fetch them separately (but batch them)
          fetch_and_process_album_tracks(album_record, spotify_album)
        end
      end
    rescue => e
      Rails.logger.error "Error processing album batch: #{e.message}"
      # Fallback to individual processing
      album_batch.each do |album|
        process_single_album(artist, album)
      end
    end

    def prepare_album_for_save(artist, spotify_album)
      album = Album.find_or_initialize_by(spotify_id: spotify_album.id)

      album.assign_attributes(
        name: spotify_album.name,
        artist_id: artist.id,
        album_type: spotify_album.album_type,
        total_tracks: spotify_album.total_tracks,
        external_urls: spotify_album.external_urls,
        href: spotify_album.href,
        images: spotify_album.images,
        release_date: spotify_album.release_date,
        uri: spotify_album.uri,
        # Store additional useful data
        available_markets: spotify_album.try(:available_markets),
        label: spotify_album.try(:label),
        popularity: spotify_album.try(:popularity)
      )

      @albums_to_batch_save << album if album.changed?
      album
    end

    def process_album_tracks(album_record, tracks)
      tracks.each do |spotify_track|
        prepare_track_for_save(album_record, spotify_track)
      end
    end

    def fetch_and_process_album_tracks(album_record, spotify_album)
      # Fetch all tracks for this album
      limit = 50
      offset = 0

      loop do
        tracks = with_rate_limit do
          spotify_album.tracks(limit: limit, offset: offset)
        end

        break if tracks.nil? || tracks.empty?

        tracks.each do |track|
          prepare_track_for_save(album_record, track)
        end

        offset += limit
        break if tracks.size < limit
      end
    end

    def prepare_track_for_save(album_record, spotify_track)
      track = Track.find_or_initialize_by(spotify_id: spotify_track.id)

      # Determine if this is a top track based on popularity
      # (We can mark popular tracks as potential top tracks)
      is_potentially_top = spotify_track.try(:popularity).to_i >= 50

      track.assign_attributes(
        title: spotify_track.name,
        album_id: album_record&.id,
        duration_ms: spotify_track.duration_ms,
        explicit: spotify_track.explicit,
        href: spotify_track.href,
        is_playable: spotify_track.try(:is_playable),
        preview_url: spotify_track.preview_url,
        track_number: spotify_track.track_number,
        uri: spotify_track.uri,
        popularity: spotify_track.try(:popularity),
        is_top_track: track.is_top_track || is_potentially_top
      )

      @tracks_to_batch_save << track if track.changed?
      track
    end

    def sync_top_tracks(artist, spotify_artist)
      # Only make this API call if we really need it
      # Check if we already have enough popular tracks from albums
      existing_top_tracks = artist.tracks.where("popularity > ?", 50).limit(10)

      if existing_top_tracks.count < 5
        Rails.logger.info "[Spotify Sync] Fetching dedicated top tracks for #{artist.name}"

        top_tracks = with_rate_limit do
          spotify_artist.top_tracks(@country)
        end

        # Clear previous top track markers
        artist.tracks.update_all(is_top_track: false)

        top_tracks.first(10).each_with_index do |spotify_track, index|
          # Find or create the track (it might already exist from album sync)
          track = Track.find_by(spotify_id: spotify_track.id)

          if track
            # Just update the top track flag and popularity
            track.update!(
              is_top_track: true,
              popularity: spotify_track.popularity || (100 - index * 10)
            )
          else
            # Need to create the track and potentially its album
            album_record = if spotify_track.album
              prepare_album_for_save(artist, spotify_track.album)
            end

            track = prepare_track_for_save(album_record, spotify_track)
            track.is_top_track = true
            track.popularity = spotify_track.popularity || (100 - index * 10)
            @tracks_to_batch_save << track
          end
        end

        # Save any new albums and tracks
        bulk_save_albums
        bulk_save_tracks
      else
        Rails.logger.info "[Spotify Sync] Using existing popular tracks as top tracks for #{artist.name}"

        # Mark the most popular existing tracks as top tracks
        existing_top_tracks.update_all(is_top_track: true)
      end
    rescue => e
      Rails.logger.error "Error syncing top tracks for #{artist.name}: #{e.message}"
    end

    def already_have_top_tracks?(artist)
      artist.tracks.where(is_top_track: true).exists?
    end

    def need_full_artist_details?
      # Determine if we need full artist details based on what we plan to do
      true # For now, always get full details, but this could be optimized
    end

    def process_single_album(artist, album)
      begin
        full_album = with_rate_limit do
          RSpotify::Album.find(album.id)
        end

        album_record = prepare_album_for_save(artist, full_album)
        fetch_and_process_album_tracks(album_record, full_album)
      rescue => e
        Rails.logger.error "Error processing album '#{album.try(:name)}': #{e.message}"
      end
    end

    def bulk_save_albums
      return if @albums_to_batch_save.empty?

      ActiveRecord::Base.transaction do
        @albums_to_batch_save.each(&:save!)
      end

      Rails.logger.info "[Spotify Sync] Saved #{@albums_to_batch_save.size} albums"
      @albums_to_batch_save.clear
    rescue => e
      Rails.logger.error "Error in bulk save albums: #{e.message}"
      # Fallback to individual saves
      @albums_to_batch_save.each do |album|
        begin
          album.save! if album.changed?
        rescue => save_error
          Rails.logger.error "Error saving album '#{album.name}': #{save_error.message}"
        end
      end
    ensure
      @albums_to_batch_save.clear
    end

    def bulk_save_tracks
      return if @tracks_to_batch_save.empty?

      ActiveRecord::Base.transaction do
        @tracks_to_batch_save.each(&:save!)
      end

      Rails.logger.info "[Spotify Sync] Saved #{@tracks_to_batch_save.size} tracks"
      @tracks_to_batch_save.clear
    rescue => e
      Rails.logger.error "Error in bulk save tracks: #{e.message}"
      # Fallback to individual saves
      @tracks_to_batch_save.each do |track|
        begin
          track.save! if track.changed?
        rescue => save_error
          Rails.logger.error "Error saving track '#{track.title}': #{save_error.message}"
        end
      end
    ensure
      @tracks_to_batch_save.clear
    end

    def with_rate_limit
      enforce_rate_limit
      @api_call_count += 1

      # Log progress in development
      if Rails.env.development? && @api_call_count % 10 == 0
        Rails.logger.debug "[Spotify Sync] #{@api_call_count} API calls made"
      end

      yield
    rescue RestClient::TooManyRequests => e
      handle_rate_limit_error(e)
      retry
    end

    def enforce_rate_limit
      return unless @rate_limit_delay && @rate_limit_delay > 0

      time_since_last_call = Time.current - @last_api_call
      if time_since_last_call < @rate_limit_delay
        sleep_time = @rate_limit_delay - time_since_last_call
        sleep(sleep_time) if sleep_time > 0
      end

      @last_api_call = Time.current
    end

    def handle_rate_limit_error(error)
      retry_after = extract_retry_after(error) || 30

      Rails.logger.warn "[Spotify Sync] Rate limited! Waiting #{retry_after} seconds before retrying..."
      sleep(retry_after)
      @last_api_call = Time.current
    end

    def extract_retry_after(error)
      return nil unless error.respond_to?(:response) && error.response

      if error.response.respond_to?(:headers)
        error.response.headers[:retry_after]&.to_i ||
          error.response.headers["retry-after"]&.to_i ||
          error.response.headers["Retry-After"]&.to_i
      end
    end
  end
end
