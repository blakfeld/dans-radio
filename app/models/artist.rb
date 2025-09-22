class Artist < ApplicationRecord
  has_many :albums
  has_many :tracks, through: :albums

  # Serialize images as JSON
  serialize :images, coder: JSON
  serialize :genres, coder: JSON

  def to_rspotify_artist
    RSpotify::Artist.find(spotify_id)
  end

  def find_or_fetch(name:)
    artist = find_by(name: name)
    return artist if artist.present?

    artist = Spotify::FindArtist.call(name: name)
    return nil unless artist

    create_from_spotify(artist)
  end

  # Create an Artist record from a Spotify artist object
  def self.create_from_spotify(spotify_artist)
    return nil unless spotify_artist

    create!(
      spotify_id: spotify_artist.id,
      name: spotify_artist.name,
      images: spotify_artist.images,
      uri: spotify_artist.uri,
      href: spotify_artist.href
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Error creating artist from Spotify data: #{e.message}"
    nil
  end

  # Update local data from Spotify
  def update_from_spotify
    spotify_artist = to_rspotify_artist
    return false unless spotify_artist

    update!(
      name: spotify_artist.name,
      images: spotify_artist.images,
      uri: spotify_artist.uri,
      href: spotify_artist.href
    )
  rescue => e
    Rails.logger.error "Error updating artist #{spotify_id} from Spotify: #{e.message}"
    false
  end

  # Get top tracks for this artist
  def top_tracks(limit: 5)
    # First check if we have cached top tracks in the database
    cached_tracks = tracks.where(is_top_track: true)
                          .order(popularity: :desc)
                          .limit(limit)

    return cached_tracks if cached_tracks.any?

    # If not cached, fetch from Spotify and cache them
    fetch_and_cache_top_tracks(limit: limit)
  end

  # Fetch top tracks from Spotify and cache them
  def fetch_and_cache_top_tracks(limit: 10, country: "US")
    return [] unless spotify_id.present?

    begin
      spotify_artist = to_rspotify_artist
      return [] unless spotify_artist

      # Get top tracks from Spotify (usually returns 10)
      spotify_tracks = spotify_artist.top_tracks(country)

      # Clear previous top tracks for this artist
      tracks.update_all(is_top_track: false)

      # Process and cache each track
      spotify_tracks.first(limit).map.with_index do |spotify_track, index|
        # Find or create the album first
        # IMPORTANT: Check if album belongs to THIS artist to avoid cross-contamination
        album_record = if spotify_track.album
          # First, try to find an album that belongs to THIS artist
          album = Album.find_by(spotify_id: spotify_track.album.id, artist_id: self.id)

          if album.nil?
            # Album doesn't exist for this artist, check if it exists for another artist
            existing_album = Album.find_by(spotify_id: spotify_track.album.id)

            if existing_album && existing_album.artist_id != self.id
              # Album exists but belongs to another artist (could be compilation, feature, etc.)
              # Create a new album record specifically for this artist
              Rails.logger.info "Album '#{spotify_track.album.name}' (#{spotify_track.album.id}) exists for another artist. Creating separate record for #{self.name}"
              album = Album.create!(
                spotify_id: spotify_track.album.id,
                name: spotify_track.album.name,
                artist_id: self.id,
                album_type: spotify_track.album.album_type,
                images: spotify_track.album.images,
                release_date: spotify_track.album.release_date,
                uri: spotify_track.album.uri,
                href: spotify_track.album.href,
                total_tracks: spotify_track.album.total_tracks
              )
            else
              # Album doesn't exist at all, create it
              album = Album.find_or_create_by(spotify_id: spotify_track.album.id) do |a|
                a.name = spotify_track.album.name
                a.artist_id = self.id
                a.album_type = spotify_track.album.album_type
                a.images = spotify_track.album.images
                a.release_date = spotify_track.album.release_date
                a.uri = spotify_track.album.uri
                a.href = spotify_track.album.href
                a.total_tracks = spotify_track.album.total_tracks
              end
            end
          end

          album
        end

        # Find or create the track
        # IMPORTANT: Associate track with the correct album for THIS artist
        track = Track.find_by(spotify_id: spotify_track.id, album_id: album_record&.id)

        if track.nil?
          # Check if track exists with a different album
          existing_track = Track.find_by(spotify_id: spotify_track.id)

          if existing_track && existing_track.album.artist_id != self.id
            # Track exists but is associated with a different artist's album
            Rails.logger.info "Track '#{spotify_track.name}' (#{spotify_track.id}) exists for another artist. Creating separate record for #{self.name}"
            track = Track.create!(
              spotify_id: spotify_track.id,
              title: spotify_track.name,
              album_id: album_record&.id,
              duration_ms: spotify_track.duration_ms,
              explicit: spotify_track.explicit,
              href: spotify_track.href,
              is_playable: spotify_track.is_playable,
              preview_url: spotify_track.preview_url,
              track_number: spotify_track.track_number,
              uri: spotify_track.uri
            )
          else
            # Track doesn't exist or belongs to this artist, find or create it
            track = Track.find_or_create_by(spotify_id: spotify_track.id) do |t|
              t.title = spotify_track.name
              t.album_id = album_record&.id
              t.duration_ms = spotify_track.duration_ms
              t.explicit = spotify_track.explicit
              t.href = spotify_track.href
              t.is_playable = spotify_track.is_playable
              t.preview_url = spotify_track.preview_url
              t.track_number = spotify_track.track_number
              t.uri = spotify_track.uri
            end

            # Ensure the track is associated with the correct album
            if track.album_id != album_record&.id
              track.update!(album_id: album_record&.id)
            end
          end
        end

        # Update top track status and popularity
        track.update!(
          is_top_track: true,
          popularity: spotify_track.popularity || (100 - index * 10) # Fallback popularity based on order
        )

        track
      end
    rescue => e
      Rails.logger.error "Error fetching top tracks for artist #{name}: #{e.message}"
      []
    end
  end
end
