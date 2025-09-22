class RequestsController < ApplicationController
  before_action :check_request_cooldown, only: [ :new, :create ]
  before_action :set_track, only: [ :new, :create ]

  def new
    if in_cooldown?
      redirect_to browse_path, alert: "Please wait #{@cooldown_remaining} seconds before making another request"
      return
    end

    @request = SongRequest.new
  end

  def create
    if in_cooldown?
      redirect_to browse_path, alert: "Please wait before making another request"
      return
    end

    # Get or create the singleton request queue
    queue = RequestQueue.get

    @request = SongRequest.new(
      track: @track,
      track_id: @track.spotify_id,
      artist: @track.artist&.name,
      track_title: @track.title,
      track_uri: @track.uri,
      request_queue: queue,
      status: "pending",
      state: "pending"
    )

    if @request.save
      # Set the position for the request
      @request.update(position: queue.song_requests.maximum(:position).to_i + 1)

      # Update session with last request time
      session[:last_request_time] = Time.current.to_s
      session[:last_request_id] = @request.id

      # Try to enqueue the request
      begin
        EnqueueSongRequest.call(song_request: @request)
      rescue => e
        Rails.logger.error "Error enqueueing request: #{e.message}"
      end

      redirect_to confirmation_requests_path
    else
      flash[:alert] = "Unable to create request: #{@request.errors.full_messages.join(', ')}"
      redirect_to browse_path
    end
  end

  def confirmation
    @request = if session[:last_request_id]
      SongRequest.find_by(id: session[:last_request_id])
    end

    # Get the overall queue status
    @queue_status = GetQueuePosition.call

    # Get this specific request's position if it exists
    @queue_position = @request&.position
  end

  def index
    @pending_requests = SongRequest.active
                                  .includes(:track)
                                  .order(position: :asc)
    @currently_playing = SongRequest.playing.first
  end

  private

  def set_track
    @track = Track.find(params[:track_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to browse_path, alert: "Track not found"
  end

  def check_request_cooldown
    @can_request = !in_cooldown?
    @cooldown_remaining = cooldown_remaining_seconds if in_cooldown?
  end

  def in_cooldown?
    last_request_time = session[:last_request_time]
    return false unless last_request_time

    time_since_request = Time.current - Time.parse(last_request_time)
    time_since_request < cooldown_period
  end

  def cooldown_remaining_seconds
    return 0 unless session[:last_request_time]

    last_request = Time.parse(session[:last_request_time])
    remaining = cooldown_period - (Time.current - last_request)
    [ remaining.to_i, 0 ].max
  end

  def cooldown_period
    5.minutes
  end
end
