class ManagePlayState < ApplicationService
  def call
    begin
      Spotify::ManagePlayback.call(should_play: true)
      { success: true, playing: true }
    rescue => e
      Rails.logger.error "[ManagePlayState] Error: #{e.message}"
      { error: e.message, success: false }
    end
  end
end
