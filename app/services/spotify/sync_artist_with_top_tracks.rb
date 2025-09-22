module Spotify
  class SyncArtistWithTopTracks < ApplicationService
    attr_reader :artist_name, :spotify_artist_id, :fetch_top_tracks, :country

    def initialize(artist_name: nil, spotify_artist_id: nil, fetch_top_tracks: true, country: "US")
      @artist_name = artist_name
      @spotify_artist_id = spotify_artist_id
      @fetch_top_tracks = fetch_top_tracks
      @country = country

      unless artist_name.present? || spotify_artist_id.present?
        raise ArgumentError, "Either artist_name or spotify_artist_id must be provided"
      end
    end

    def call
      # Find or fetch the Spotify artist
      spotify_artist = find_spotify_artist
      return nil unless spotify_artist

      # Create or update the artist in our database
      artist = sync_artist(spotify_artist)

      # Sync albums
      sync_albums(artist, spotify_artist) if artist

      # Fetch and cache top tracks if requested
      if fetch_top_tracks && artist
        artist.fetch_and_cache_top_tracks(limit: 10, country: country)
      end

      artist
    end

    private

    def find_spotify_artist
      if spotify_artist_id.present?
        RSpotify::Artist.find(spotify_artist_id)
      elsif artist_name.present?
        results = RSpotify::Artist.search(artist_name, limit: 1)
        results.first
      end
    rescue => e
      Rails.logger.error "Error finding Spotify artist: #{e.message}"
      nil
    end

    def sync_artist(spotify_artist)
      artist = Artist.find_or_initialize_by(spotify_id: spotify_artist.id)

      artist.update!(
        name: spotify_artist.name,
        images: spotify_artist.images,
        uri: spotify_artist.uri,
        href: spotify_artist.href,
        genres: spotify_artist.genres,
        popularity: spotify_artist.popularity
      )

      artist
    rescue => e
      Rails.logger.error "Error syncing artist: #{e.message}"
      nil
    end

    def sync_albums(artist, spotify_artist)
      # Fetch albums (limit to 20 most recent)
      albums = spotify_artist.albums(limit: 20, album_type: "album,single", country: country)

      albums.each do |spotify_album|
        album = Album.find_or_initialize_by(spotify_id: spotify_album.id)

        album.update!(
          name: spotify_album.name,
          artist_id: artist.id,
          album_type: spotify_album.album_type,
          total_tracks: spotify_album.total_tracks,
          external_urls: spotify_album.external_urls,
          href: spotify_album.href,
          images: spotify_album.images,
          release_date: spotify_album.release_date,
          uri: spotify_album.uri
        )
      end
    rescue => e
      Rails.logger.error "Error syncing albums for artist #{artist.name}: #{e.message}"
    end
  end
end
