class DequeueSongRequest < ApplicationService
  def initialize(track: nil, song_request_id: nil)
    @track = track
    @song_request_id = song_request_id
  end

  def call
    # Get the singleton queue
    request_queue = RequestQueue.get

    if @song_request_id
      # Remove by song request ID
      song_request = request_queue.song_requests.find_by(id: @song_request_id)
      return { success: false, error: "Song request not found" } unless song_request

      track = song_request.track
      request_queue.dequeue(track)

      {
        success: true,
        message: "Removed #{track.title} from queue"
      }
    elsif @track
      # Remove by track
      request_queue.dequeue(@track)

      {
        success: true,
        message: "Removed #{@track.title} from queue"
      }
    else
      {
        success: false,
        error: "Must provide either track or song_request_id"
      }
    end
  rescue => e
    Rails.logger.error "Failed to dequeue song request: #{e.message}"
    {
      success: false,
      error: e.message
    }
  end
end
