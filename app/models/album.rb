class Album < ApplicationRecord
  belongs_to :artist
  has_many :tracks

  # Serialize complex fields as JSON
  serialize :images, coder: JSON
  serialize :external_urls, coder: JSON

  def to_rspotify_album
    RSpotify::Album.find(spotify_id)
  end

  def find_or_fetch(name: nil, artist: nil, spotify_id: nil)
    if spotify_id.present?
      album = find_by(spotify_id: spotify_id)
      return album if album.present?
    elsif name.present? && artist.present?
      album = find_by(name: name, artist: artist)
      return album if album.present?
    else
      raise "Either name, artist, or spotify_id must be present"
    end

    create_from_spotify(album)
  end

  # Create an Album record from a Spotify album object
  def self.create_from_spotify(spotify_album)
    return nil unless spotify_album

    # Ensure we have the artist first
    artist_record = if spotify_album.artists.any?
      primary_artist = spotify_album.artists.first
      Artist.find_by_spotify_id(primary_artist.id)
    end

    create!(
      spotify_id: spotify_album.id,
      name: spotify_album.name,
      artist_id: artist_record&.id,
      album_type: spotify_album.album_type,
      total_tracks: spotify_album.total_tracks,
      external_urls: spotify_album.external_urls,
      href: spotify_album.href,
      images: spotify_album.images,
      release_date: spotify_album.release_date,
      uri: spotify_album.uri
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Error creating album from Spotify data: #{e.message}"
    nil
  end

  # Update local data from Spotify
  def update_from_spotify
    spotify_album = to_rspotify_album
    return false unless spotify_album

    # Update artist if needed
    if spotify_album.artists.any?
      primary_artist = spotify_album.artists.first
      artist_record = Artist.find_by_spotify_id(primary_artist.id)
      self.artist_id = artist_record&.id if artist_record
    end

    update!(
      name: spotify_album.name,
      album_type: spotify_album.album_type,
      total_tracks: spotify_album.total_tracks,
      external_urls: spotify_album.external_urls,
      href: spotify_album.href,
      images: spotify_album.images,
      release_date: spotify_album.release_date,
      uri: spotify_album.uri
    )
  rescue => e
    Rails.logger.error "Error updating album #{spotify_id} from Spotify: #{e.message}"
    false
  end
end
