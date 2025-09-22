class Track < ApplicationRecord
  belongs_to :album
  has_one :artist, through: :album

  def to_rspotify_track
    RSpotify::Track.find(spotify_id)
  end

  def find_or_fetch(album:, title:, spotify_id: nil)
    if spotify_id.present?
      track = find_by(spotify_id: spotify_id)
      return track if track.present?
    elsif album.present? && title.present?
      track = find_by(album: album, title: title)
      return track if track.present?
    else
      raise "Either album, title, or spotify_id must be present"
    end

    create_from_spotify(track)
  end

  # Find track by Spotify ID, or fetch from API if not found locally
  def self.find_by_spotify_id(spotify_id)
    return nil if spotify_id.blank?

    # Try to find locally first
    track = find_by(spotify_id: spotify_id)
    return track if track.present?

    # Not found locally, fetch from Spotify
    begin
      spotify_track = RSpotify::Track.find(spotify_id)
      return nil unless spotify_track

      # Create the track record with all the data
      create_from_spotify(spotify_track)
    rescue => e
      Rails.logger.error "Error fetching track #{spotify_id} from Spotify: #{e.message}"
      nil
    end
  end

  # Create a Track record from a Spotify track object
  def self.create_from_spotify(spotify_track)
    return nil unless spotify_track

    # Ensure we have the album first (which will also ensure artist)
    album_record = if spotify_track.album
      Album.find_by_spotify_id(spotify_track.album.id)
    end

    create!(
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
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Error creating track from Spotify data: #{e.message}"
    nil
  end

  # Update local data from Spotify
  def update_from_spotify
    spotify_track = to_rspotify_track
    return false unless spotify_track

    # Update album if needed
    if spotify_track.album
      album_record = Album.find_by_spotify_id(spotify_track.album.id)
      self.album_id = album_record&.id if album_record
    end

    update!(
      title: spotify_track.name,
      duration_ms: spotify_track.duration_ms,
      explicit: spotify_track.explicit,
      href: spotify_track.href,
      is_playable: spotify_track.is_playable,
      preview_url: spotify_track.preview_url,
      track_number: spotify_track.track_number,
      uri: spotify_track.uri
    )
  rescue => e
    Rails.logger.error "Error updating track #{spotify_id} from Spotify: #{e.message}"
    false
  end

  # Convenience method to get duration in a human-readable format
  def duration_formatted
    return nil unless duration_ms

    seconds = duration_ms / 1000
    minutes = seconds / 60
    remaining_seconds = seconds % 60

    format("%d:%02d", minutes, remaining_seconds)
  end
end
