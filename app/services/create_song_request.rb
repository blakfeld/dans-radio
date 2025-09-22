class CreateSongRequest < ApplicationService
  def initialize(track_id:, artist:, track_title:)
    @track_id = track_id
    @artist = artist
    @track_title = track_title
  end

  def call
    SongRequest.create!(
      artist: artist,
      track_id: track.id,
      track_title: track.name,
    )
  end

  private

  def artist
    Artist.find_or_fetch(name: @artist_name)
  end

  def album
    Album.find_or_fetch(name: @album_name, artist: artist)
  end

  def track
    Track.find_or_fetch(album: @album, title: @track_title, spotify_id: @track_id)
  end
end
