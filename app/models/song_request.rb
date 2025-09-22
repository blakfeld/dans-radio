class SongRequest < ApplicationRecord
  belongs_to :request_queue
  belongs_to :track, optional: true

  # Status values for tracking request lifecycle
  STATUSES = %w[pending queued playing played failed recovered].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :position, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :pending, -> { where(status: "pending") }
  scope :queued, -> { where(status: "queued") }
  scope :playing, -> { where(status: "playing") }
  scope :played, -> { where(status: "played") }
  scope :active, -> { where(status: [ "pending", "queued", "playing" ]) }

  # Get the associated track as an RSpotify object
  def spotify_track
    return nil unless track
    track.to_rspotify_track
  end

  # Check if this request is currently being played
  def playing?
    status == "playing"
  end

  # Check if this request has been played
  def played?
    status == "played"
  end

  # Check if this request is still active in the queue
  def active?
    [ "pending", "queued", "playing" ].include?(status)
  end
end
