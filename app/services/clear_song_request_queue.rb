class ClearSongRequestQueue < ApplicationService
  def call
    # Get the singleton queue
    request_queue = RequestQueue.get

    # Clear the queue
    request_queue.clear!

    # Stop processing job
    ProcessRequestQueueJob.stop_processing

    {
      success: true,
      message: "Queue cleared successfully"
    }
  rescue => e
    Rails.logger.error "Failed to clear queue: #{e.message}"
    {
      success: false,
      error: e.message
    }
  end
end
