module ApplicationHelper
  def format_time_ms(milliseconds)
    return "0:00" if milliseconds.nil? || milliseconds == 0

    seconds = milliseconds / 1000
    minutes = seconds / 60
    remaining_seconds = seconds % 60

    format("%d:%02d", minutes, remaining_seconds)
  end
end
