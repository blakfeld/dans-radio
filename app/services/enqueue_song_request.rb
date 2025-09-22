class EnqueueSongRequest < ApplicationService
  def initialize(track:, requester: nil)
    @track = track
    @requester = requester
  end

  def call
    # Get the singleton queue
    request_queue = RequestQueue.get

    # Enqueue the track
    song_request = request_queue.enqueue(@track, requester: @requester)

    # Start processing if not already running
    ProcessRequestQueueJob.start_processing

    {
      success: true,
      song_request: song_request,
      position: song_request.position,
      message: "#{@track.title} added to queue at position #{song_request.position + 1}"
    }
  rescue => e
    Rails.logger.error "Failed to enqueue song request: #{e.message}"
    {
      success: false,
      error: e.message
    }
  end
end
