# Dan's Radio 📻

![Test Suite](https://github.com/corwinbrown/dans_radio/workflows/Test%20Suite/badge.svg)
![Ruby](https://img.shields.io/badge/Ruby-3.3.0-red)
![Rails](https://img.shields.io/badge/Rails-8.0.2-red)
![Coverage](https://img.shields.io/badge/Coverage-90%25+-green)

An interactive music request system for Dan's Silverleaf as part of the Denton Diorama Collective's Halloween exhibit. Dan's Radio plays music from local Denton bands continuously while allowing exhibit viewers to request songs through an intuitive web interface.

## Overview

Dan's Radio is a Rails application that bridges Spotify's API with a custom request queue system to create an interactive radio experience. The system maintains two Spotify playlists:

1. **Dan's Radio** - The main playlist containing curated local Denton bands that plays continuously
2. **Dan's Radio Queue** - A dynamic playlist that manages user-requested songs

When users make requests, the system seamlessly switches from the radio playlist to the queue playlist, plays through the requested songs, then returns to the regular radio programming.

## Features

### For Exhibit Visitors
- 🎵 Browse local Denton artists and their music catalog
- 🔍 Search and discover tracks from featured bands
- 📝 Request songs to be played next
- 🎧 View currently playing track and upcoming queue
- 👀 See artist bios and promotional material

### For Administrators
- 🎛️ Manage song request queue
- 👤 Control Spotify authentication and playlist settings
- 📊 Monitor system status and playback state
- 🗑️ Clear queue and manage requests
- 🎨 Admin dashboard for system oversight

## Technical Architecture

### Core Components

#### 1. **Request Queue System**
- Singleton pattern for single station-wide queue
- Automatic position management and reordering
- Status tracking (pending → queued → playing → played)
- Spotify playlist synchronization

#### 2. **Background Job Processing**
The system uses Rails' Solid Queue for reliable background job processing:

- **TrackPlayheadJob** - Monitors playback progress every 30 seconds
- **UpdateStateJob** - Syncs system state with Spotify every minute
- **SyncQueuePlaylistJob** - Maintains playlist consistency every 5 minutes
- **ProcessRequestQueueJob** - Dynamically processes queue based on playback state
- **ClearOldSongRequestsJob** - Cleans up old requests hourly
- **RefreshSpotifyTokensJob** - Keeps Spotify authentication fresh

#### 3. **Spotify Integration**
- OAuth 2.0 authentication flow
- Real-time playback monitoring
- Playlist management (create, update, clear)
- Track queueing and removal
- Artist and album data synchronization

#### 4. **Data Models**
- **Artist** - Local Denton bands with bios and Spotify metadata
- **Album** - Album information with release dates and artwork
- **Track** - Individual songs with duration and playability status
- **SongRequest** - User requests with status tracking
- **RequestQueue** - Singleton queue manager
- **SpotifyUser** - OAuth credentials storage
- **User** - Admin user management

### How It Works

1. **Initial Setup**
   - Admin authenticates with Spotify through OAuth
   - System creates/locates the two required playlists
   - Artists from the main playlist are synced to the database
   - Albums and tracks are cached for quick browsing

2. **Normal Operation**
   - The "Dan's Radio" playlist plays continuously
   - Background jobs monitor the current playback state
   - Users browse artists and request songs through the web UI

3. **Request Processing**
   - User requests are added to the internal queue
   - Every minute, the system syncs the internal queue with the Spotify queue playlist
   - When the queue has songs, playback switches to the queue playlist
   - As songs play, they're marked complete and removed from both queues

4. **Queue Management**
   - The system tracks playhead position through the queue
   - Completed songs are automatically removed
   - When the queue empties, playback returns to the radio playlist
   - Old requests are cleaned up after being played

## Tech Stack

- **Framework**: Rails 8.0.2
- **Database**: SQLite 3
- **Job Queue**: Solid Queue
- **Cache**: Solid Cache
- **WebSockets**: Solid Cable
- **Frontend**: Hotwire (Turbo + Stimulus)
- **CSS**: Tailwind CSS (via CDN)
- **Spotify Integration**: RSpotify gem
- **Server**: Puma
- **Deployment**: Docker-ready with Kamal support

## Setup

### Prerequisites
- Ruby 3.x
- Rails 8.0.2+
- SQLite 3
- Spotify Developer Account with API credentials
- Node.js (for asset compilation)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/dans_radio.git
   cd dans_radio
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Configure Spotify credentials**
   ```bash
   rails credentials:edit
   ```

   Add your Spotify credentials:
   ```yaml
   spotify:
     client_id: your_client_id_here
     client_secret: your_client_secret_here
   ```

4. **Setup database**
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed  # Optional: loads demo data
   ```

5. **Configure playlists**
   Edit `config/application.rb` to set your Spotify username and playlist names:
   ```ruby
   config.spotify = {
     user_name: "your_spotify_username",
     request_playlist_name: "Dans Radio Queue",
     radio_playlist_name: "Dans Radio"
   }
   ```

6. **Start the server**
   ```bash
   rails server
   ```

   For SSL in development (required for Spotify OAuth):
   ```bash
   ./start_ssl_with_forward.sh
   ```

7. **Authenticate with Spotify**
   - Navigate to `/setup`
   - Click "Authenticate with Spotify"
   - Grant permissions
   - System will create playlists if they don't exist

8. **Start background jobs**
   ```bash
   rails solid_queue:start
   ```

## Usage

### For Exhibit Visitors

1. **Browse Artists**: Visit the home page to see currently playing and browse artists
2. **Make Requests**: Click on an artist, select a song, and request it
3. **View Queue**: Check the queue page to see upcoming songs
4. **Track Progress**: Watch the now playing section for real-time updates

### For Administrators

1. **Access Admin Panel**: Navigate to `/admin`
2. **Manage Requests**: Approve, reject, or clear the queue
3. **Monitor System**: Check Spotify connection status in `/setup`
4. **View Logs**: Monitor background job execution in logs

## Development

### Running Tests

This application has comprehensive test coverage (90%+) across all components including models, services, controllers, jobs, and helpers.

```bash
# Run all tests with coverage report
rake test:coverage
# or
COVERAGE=true rails test

# Run specific test categories
rails test test/models      # Model tests
rails test test/controllers # Controller tests
rails test test/services    # Service tests
rails test test/jobs        # Background job tests
rails test test/helpers     # Helper tests

# Run system tests
rails test:system

# View HTML coverage report
open coverage/index.html

# Quick coverage summary
rake test:summary
```

#### Test Coverage Goals
- **Overall**: 90%+ coverage
- **Models**: 95%+ coverage
- **Services**: 90%+ coverage
- **Controllers**: 85%+ coverage
- **Jobs**: 85%+ coverage

#### Continuous Integration
Tests run automatically via GitHub Actions on:
- Every push to main/master/develop branches
- All pull requests
- Nightly builds with extended coverage analysis
- See [.github/workflows/](.github/workflows/) for CI configuration

### Console Helpers
The app includes helpful console methods for debugging:
```ruby
rails console

# Get current Spotify user
spotify_user

# Check current playing track
currently_playing

# View queue status
RequestQueue.get.upcoming_tracks
```

### Key Rake Tasks
```bash
# Sync artists from main playlist
rails spotify:sync_artists

# Test queue operations
rails queue:test

# Load demo data
rails demo:load
```

## Deployment

The application is Docker-ready and configured for deployment with Kamal:

```bash
# Build and deploy
kamal deploy

# Check deployment status
kamal app details
```

## Configuration

### Environment Variables
- `RAILS_MASTER_KEY` - Rails credentials key
- `DATABASE_URL` - Production database connection
- `REDIS_URL` - Redis connection for Action Cable (optional)

### Spotify App Settings
In your Spotify App settings, configure:
- **Redirect URI**: `https://yourdomain.com/auth/spotify/callback`
- **Scopes Required**:
  - `user-read-playback-state`
  - `user-modify-playback-state`
  - `playlist-read-private`
  - `playlist-modify-private`
  - `playlist-modify-public`

## Architecture Decisions

- **Singleton Queue**: Ensures one unified queue for the entire exhibit
- **Playlist-based Queueing**: More reliable than Spotify's native queue API
- **Polling Strategy**: Regular state checks ensure consistency with Spotify
- **Local Data Cache**: Reduces API calls and improves response times
- **Job-based Processing**: Reliable background processing with automatic retries

## Troubleshooting

### Common Issues

1. **Spotify Authentication Expires**
   - Visit `/setup` and re-authenticate
   - Background job automatically refreshes tokens hourly

2. **Queue Out of Sync**
   - System auto-recovers from Spotify playlist state
   - Manual sync available in admin panel

3. **Songs Not Playing**
   - Check Spotify premium account is active
   - Verify playlist exists and has tracks
   - Check logs for API errors

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is proprietary software created for the Denton Diorama Collective's Halloween exhibit.

## Acknowledgments

- Dan's Silverleaf for hosting the exhibit
- Denton Diorama Collective for the opportunity
- All the amazing Denton bands featured on the station
- Spotify for their comprehensive API

---

Built with ❤️ for the Denton music community
