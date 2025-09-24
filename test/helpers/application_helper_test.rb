require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # format_time_ms tests
  test "formats milliseconds to time string correctly" do
    assert_equal "0:00", format_time_ms(0)
    assert_equal "0:00", format_time_ms(nil)
    assert_equal "1:00", format_time_ms(60000)
    assert_equal "3:30", format_time_ms(210000)
    assert_equal "10:05", format_time_ms(605000)
    assert_equal "59:59", format_time_ms(3599000)
    assert_equal "60:00", format_time_ms(3600000)
  end

  test "handles edge cases for time formatting" do
    assert_equal "0:01", format_time_ms(1000)
    assert_equal "0:59", format_time_ms(59000)
    assert_equal "100:00", format_time_ms(6000000)
  end

  test "pads seconds with leading zero" do
    assert_equal "1:01", format_time_ms(61000)
    assert_equal "2:09", format_time_ms(129000)
    assert_equal "5:00", format_time_ms(300000)
  end

  test "handles negative values gracefully" do
    # Ruby's integer division handles negatives differently
    # but the helper should still produce output
    result = format_time_ms(-60000)
    assert_not_nil result
  end

  test "handles very large values" do
    # 1 hour = 3,600,000 ms
    assert_equal "60:00", format_time_ms(3600000)
    # 2 hours = 7,200,000 ms
    assert_equal "120:00", format_time_ms(7200000)
    # 24 hours = 86,400,000 ms
    assert_equal "1440:00", format_time_ms(86400000)
  end

  test "handles fractional milliseconds by truncating" do
    assert_equal "1:00", format_time_ms(60500.5)
    assert_equal "0:01", format_time_ms(1999.9)
  end
end
