# Dan's Radio Test Suite

## Overview
This test suite provides comprehensive coverage for the Dan's Radio application, including models, services, jobs, controllers, and helpers.

## Test Structure

```
test/
├── controllers/       # Controller tests
├── helpers/          # Helper module tests
├── jobs/             # Background job tests
├── models/           # Model tests
├── services/         # Service object tests
├── fixtures/         # Test data fixtures
└── test_helper.rb    # Test configuration and helpers
```

## Running Tests

### Run All Tests
```bash
rails test
```

### Run Tests with Coverage Report
```bash
bin/test_with_coverage
# or
COVERAGE=true rails test
```

### Run Specific Test Files
```bash
rails test test/models/track_test.rb
rails test test/controllers/requests_controller_test.rb
```

### Run Specific Test Categories
```bash
rails test test/models
rails test test/controllers
rails test test/services
rails test test/jobs
```

### Run a Single Test Method
```bash
rails test test/models/track_test.rb:15
```

## Test Coverage

The test suite includes:

### Models (100% coverage target)
- `Track` - Spotify track integration, finding, creating, updating
- `Album` - Album management and Spotify sync
- `Artist` - Artist management, top tracks functionality
- `SongRequest` - Request lifecycle and status management
- `SpotifyUser` - OAuth integration and token refresh
- `RequestQueue` - Singleton queue management and Spotify sync

### Services
- `ManageCurrentlyPlaying` - Playlist switching logic
- `UpdatePlayhead` - Track progress monitoring
- Additional Spotify service integrations

### Jobs
- `RefreshSpotifyTokensJob` - Token renewal automation
- `ProcessRequestQueueJob` - Queue processing and sync
- Additional background job coverage

### Controllers
- `NowPlayingController` - Current playback and browsing
- `RequestsController` - Song request management
- `BrowseController` - Artist/track discovery
- `AuthController` - Authentication flow

### Helpers
- `ApplicationHelper` - Time formatting utilities

## Test Utilities

### Mock Helpers
The test suite includes comprehensive mock helpers for Spotify API objects:

```ruby
mock_spotify_track(attrs = {})
mock_spotify_album(attrs = {})
mock_spotify_artist(attrs = {})
mock_spotify_user(attrs = {})
mock_spotify_playlist(attrs = {})
```

### Assertions
Custom assertions for service objects:

```ruby
assert_service_success(result)
assert_service_failure(result)
assert_enqueued_with_job(JobClass, args: expected_args)
```

## Dependencies

The test suite uses:
- **Minitest** - Rails default testing framework
- **WebMock** - HTTP request stubbing
- **VCR** - Record and replay HTTP interactions
- **SimpleCov** - Code coverage analysis
- **Factory Bot** - Test data generation
- **Faker** - Realistic test data

## Coverage Reports

After running tests with coverage enabled, view the HTML report:

```bash
open coverage/index.html
```

Coverage goals:
- Models: 95%+
- Services: 90%+
- Controllers: 85%+
- Jobs: 85%+
- Overall: 90%+

## Best Practices

1. **Isolation**: Each test should be independent
2. **Setup/Teardown**: Use `setup` and `teardown` blocks appropriately
3. **Mocking**: Mock external services (Spotify API) consistently
4. **Fixtures**: Use fixtures for static test data
5. **Factories**: Use factories for dynamic test data
6. **Coverage**: Aim for high coverage but focus on meaningful tests

## Continuous Integration

The test suite is designed to run in CI environments:

```bash
# CI test command
RAILS_ENV=test bundle exec rails db:test:prepare
RAILS_ENV=test COVERAGE=true bundle exec rails test
```

## Troubleshooting

### Database Issues
```bash
rails db:test:prepare
rails db:test:reset
```

### Clear Test Cache
```bash
rm -rf tmp/cache/test
```

### Run Tests in Verbose Mode
```bash
rails test -v
```

### Check for N+1 Queries
Tests include associations to prevent N+1 queries. Watch for:
- Excessive database queries in test output
- Slow test execution
- Use `includes()` in controllers and services

## Contributing

When adding new features:
1. Write tests first (TDD approach)
2. Ensure all tests pass
3. Maintain or improve coverage
4. Update this README if test structure changes

