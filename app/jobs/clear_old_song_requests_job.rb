class ClearOldSongRequestsJob < ApplicationJob
  queue_as :maintenance

  def perform(days_old = 1)
    # Clear song requests older than specified days
    cutoff_date = days_old.days.ago

    old_requests = SongRequest.where("created_at < ?", cutoff_date)
    count = old_requests.count

    old_requests.destroy_all

    Rails.logger.info "Cleared #{count} song requests older than #{days_old} days"
  end
end
