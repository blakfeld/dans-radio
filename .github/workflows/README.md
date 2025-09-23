# GitHub Actions CI/CD Configuration

## Overview
This directory contains GitHub Actions workflows for continuous integration and deployment of Dan's Radio.

## Workflows

### 1. Test Suite (`test.yml`)
**Trigger:** On every push and pull request to main/master/develop branches
**Purpose:** Run the complete test suite with coverage reporting

**Jobs:**
- **test**: Main test job with coverage reporting
- **lint**: Run RuboCop and Brakeman security scans
- **test-matrix**: Test against multiple Ruby versions (3.2, 3.3)
- **test-categories**: Parallel testing of different test categories (models, controllers, services, jobs, helpers)

### 2. Nightly Tests (`nightly.yml`)
**Trigger:** Daily at 2 AM UTC (or manual)
**Purpose:** Extended test runs with stricter coverage requirements

**Features:**
- Full test suite including system tests
- Coverage threshold enforcement (90% minimum)
- Security and dependency audits
- Automatic issue creation on failure

## Required GitHub Secrets

Before the CI can run successfully, you need to configure the following secrets in your GitHub repository:

1. **SPOTIFY_CLIENT_ID**: Your Spotify application client ID
2. **SPOTIFY_CLIENT_SECRET**: Your Spotify application client secret

### How to Add Secrets

1. Go to your GitHub repository
2. Click on "Settings" tab
3. Navigate to "Secrets and variables" → "Actions"
4. Click "New repository secret"
5. Add each secret with the appropriate name and value

## CI Features

### Test Coverage
- Automatic coverage calculation using SimpleCov
- Coverage reports uploaded as artifacts
- Optional Codecov integration for coverage tracking
- Per-category coverage reports

### Security Scanning
- Brakeman for Ruby security vulnerabilities
- Bundle audit for dependency vulnerabilities
- Automated security checks in nightly builds

### Performance
- Parallel test execution
- Dependency caching for faster builds
- Matrix testing for multiple Ruby versions

## Local Testing

To replicate CI tests locally:

```bash
# Run full test suite with coverage
COVERAGE=true bundle exec rails test

# Run specific test category
bundle exec rails test test/models
bundle exec rails test test/controllers
bundle exec rails test test/services
bundle exec rails test test/jobs

# Run linting
bundle exec rubocop
bundle exec brakeman

# Check coverage summary
bundle exec rake test:summary
```

## Customization

### Adjusting Coverage Thresholds
Edit the coverage check in `nightly.yml`:
```ruby
if total < 90  # Change 90 to your desired threshold
```

### Adding New Test Categories
Add to the matrix in `test.yml`:
```yaml
matrix:
  category: [models, controllers, services, jobs, helpers, new_category]
```

### Changing Ruby Versions
Update `.ruby-version` and the matrix in workflows:
```yaml
ruby-version: ['3.2', '3.3', '3.4']
```

## Badges

Add these badges to your README.md:

```markdown
![Test Suite](https://github.com/YOUR_USERNAME/dans_radio/workflows/Test%20Suite/badge.svg)
![Coverage](https://codecov.io/gh/YOUR_USERNAME/dans_radio/branch/main/graph/badge.svg)
```

## Troubleshooting

### Tests Failing in CI but Passing Locally
- Check that all required environment variables are set as secrets
- Ensure database migrations are up to date
- Verify asset precompilation is working

### Coverage Reports Not Generated
- Ensure `COVERAGE=true` is set in environment
- Check SimpleCov configuration in `test_helper.rb`
- Verify coverage gem is in test group in Gemfile

### Slow CI Builds
- Check if dependency caching is working
- Consider splitting tests into more parallel jobs
- Review and optimize slow tests

## Best Practices

1. **Keep tests fast**: Aim for < 5 minute CI runs
2. **Monitor coverage**: Don't let coverage drop below thresholds
3. **Fix failures immediately**: Don't merge with failing tests
4. **Update dependencies regularly**: Use Dependabot or manual updates
5. **Review security warnings**: Address Brakeman findings promptly

