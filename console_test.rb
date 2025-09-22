# Rails Console Test Script
# This demonstrates the workaround for the @@users_credentials error
# Run in rails console: load 'console_test.rb'

puts "\n" + "=" * 60
puts "Testing RSpotify Workaround"
puts "=" * 60

# Check if we have any authenticated users
if SpotifyUser.any?
  spotify_user = SpotifyUser.last
  puts "\n✅ Found authenticated user: #{spotify_user.username}"
  puts "   Token exists: #{spotify_user.token.present?}"
  puts "   Refresh token exists: #{spotify_user.refresh_token.present?}"

  # This is the workaround - recreate the RSpotify::User from stored credentials
  puts "\n🔧 Applying workaround..."
  begin
    # Method 1: Using the model's to_rspotify_user method
    user = spotify_user.to_rspotify_user
    puts "✅ Successfully created RSpotify::User from stored credentials"

    # Test it works
    puts "\n📋 Testing Spotify API calls..."

    # Get playlists
    playlists = user.playlists(limit: 5)
    puts "Found #{playlists.size} playlists:"
    playlists.each do |playlist|
      puts "   - #{playlist.name} (#{playlist.tracks.size} tracks)"
    end

    # Store in instance variable for further testing
    @user = user
    puts "\n✅ Success! User stored in @user variable for testing"
    puts "\nYou can now use @user for testing, e.g.:"
    puts "  @user.playlists"
    puts "  @user.top_tracks(limit: 10)"
    puts "  @user.recently_played"

  rescue => e
    puts "❌ Error: #{e.message}"
    puts "\nTroubleshooting:"
    puts "1. Make sure you authenticated via browser first"
    puts "2. Check if token is expired:"
    puts "   Token expires at: #{spotify_user.expires_at}"
    puts "   Expired? #{spotify_user.token_expired?}"

    if spotify_user.token_expired?
      puts "\n3. Token is expired. Re-authenticate via browser:"
      puts "   https://dansradio.dev/auth/spotify"
    end
  end

else
  puts "\n❌ No authenticated users found!"
  puts "\nTo fix this:"
  puts "1. Start server: sudo rails s -p 443 -b 'ssl://0.0.0.0:443?key=config/certs/dansradio-key.pem&cert=config/certs/dansradio.pem'"
  puts "2. Visit: https://dansradio.dev/"
  puts "3. Click 'Login with Spotify'"
  puts "4. After authenticating, run this script again"
end

puts "\n" + "=" * 60
puts "Alternative: Use Service Classes"
puts "=" * 60

# Test the service classes which have the workaround built in
begin
  # This should work automatically with the workaround
  service = Spotify::GetPlaylist.new(name: "Discover Weekly", id: nil)
  playlist = service.call

  if playlist
    puts "✅ Service class works! Found: #{playlist.name}"
  else
    puts "❌ Could not find playlist"
  end
rescue => e
  puts "❌ Service error: #{e.message}"
end

puts "\n" + "=" * 60
