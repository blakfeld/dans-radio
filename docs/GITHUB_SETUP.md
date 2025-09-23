# GitHub Repository Setup for CI/CD

This guide walks you through setting up your GitHub repository to run the automated test suite and CI/CD pipelines.

## Prerequisites

- GitHub repository for the project
- Admin access to the repository
- Spotify API credentials (Client ID and Secret)

## Step 1: Add Repository Secrets

The CI pipeline requires Spotify API credentials to run tests. Add these as GitHub secrets:

1. Navigate to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add the following secrets:

### Required Secrets

| Secret Name | Description | Where to Find |
|------------|-------------|---------------|
| `SPOTIFY_CLIENT_ID` | Your Spotify app's Client ID | [Spotify Dashboard](https://developer.spotify.com/dashboard) |
| `SPOTIFY_CLIENT_SECRET` | Your Spotify app's Client Secret | [Spotify Dashboard](https://developer.spotify.com/dashboard) |

### Optional Secrets (for deployment)

| Secret Name | Description |
|------------|-------------|
| `RAILS_MASTER_KEY` | Rails credentials master key (from `config/master.key`) |
| `DOCKER_USERNAME` | Docker Hub username (if using Docker deployment) |
| `DOCKER_PASSWORD` | Docker Hub password (if using Docker deployment) |

## Step 2: Enable GitHub Actions

1. Go to **Settings** → **Actions** → **General**
2. Under "Actions permissions", select **Allow all actions and reusable workflows**
3. Under "Workflow permissions", select **Read and write permissions**
4. Check **Allow GitHub Actions to create and approve pull requests**
5. Click **Save**

## Step 3: Configure Branch Protection (Recommended)

Protect your main branch with CI requirements:

1. Go to **Settings** → **Branches**
2. Click **Add rule**
3. Enter branch name pattern: `main` (or `master`)
4. Check the following:
   - ✅ Require a pull request before merging
   - ✅ Require status checks to pass before merging
   - ✅ Require branches to be up to date before merging
5. Under "Status checks that are required", select:
   - `Tests`
   - `Linting`
6. Click **Create**

## Step 4: Add Status Badges

Add these badges to your README.md to show CI status:

```markdown
![Test Suite](https://github.com/YOUR_USERNAME/dans_radio/workflows/Test%20Suite/badge.svg)
![Nightly Build](https://github.com/YOUR_USERNAME/dans_radio/workflows/Nightly%20Test%20Run/badge.svg)
```

Replace `YOUR_USERNAME` with your GitHub username.

## Step 5: Configure Codecov (Optional)

For detailed coverage tracking:

1. Sign up at [codecov.io](https://codecov.io)
2. Add your repository
3. Copy the upload token
4. Add as GitHub secret: `CODECOV_TOKEN`
5. The workflow will automatically upload coverage reports

## Step 6: Set Up Dependabot (Optional)

Keep dependencies up to date automatically:

1. Create `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "bundler"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

## Step 7: Verify Setup

1. Make a test commit and push:
```bash
git checkout -b test-ci
echo "# Test CI" >> README.md
git add README.md
git commit -m "Test CI pipeline"
git push origin test-ci
```

2. Create a pull request
3. Check that all status checks run and pass
4. Verify coverage reports are generated

## Workflow Triggers

### Automatic Triggers
- **On Push**: Tests run on every push to main/master/develop
- **On PR**: Tests run on all pull requests
- **Nightly**: Extended tests run at 2 AM UTC daily

### Manual Triggers
- Go to **Actions** tab
- Select a workflow
- Click **Run workflow**
- Choose branch and click **Run workflow**

## Troubleshooting

### Tests Pass Locally but Fail in CI

**Check environment variables:**
- Ensure all secrets are set correctly
- Verify no hardcoded values in tests

**Database issues:**
```yaml
# Ensure test database is created
- run: rails db:test:prepare
```

**Asset compilation:**
```yaml
# If assets are needed for tests
- run: rails assets:precompile
```

### Workflow Not Running

**Check triggers:**
- Verify branch names in workflow match your branches
- Ensure workflows are not disabled in Settings

**Check syntax:**
```bash
# Validate workflow syntax locally
npm install -g @actions/workflow-parser
workflow-parser .github/workflows/test.yml
```

### Coverage Not Uploading

**Verify coverage is generated:**
- Check `COVERAGE=true` is set
- Ensure SimpleCov is configured in `test_helper.rb`

**Check artifact upload:**
- Look for "Upload coverage reports" step in workflow
- Download artifacts from Actions run to inspect

## Local Development

Before pushing, run local CI checks:

```bash
# Quick checks
bin/ci quick

# Full suite
bin/ci full

# With coverage
bin/ci coverage
```

Install pre-push hook:
```bash
bin/setup_ci
```

## Support

For issues with:
- **GitHub Actions**: Check [GitHub Actions Documentation](https://docs.github.com/en/actions)
- **Test failures**: Review test output in Actions tab
- **Coverage**: Check SimpleCov configuration

## Next Steps

After CI is working:
1. Set up deployment workflows
2. Add performance benchmarks
3. Configure staging environment tests
4. Set up notification integrations (Slack, email, etc.)

