# RuboCop Setup Documentation

## Overview

This repository has multiple layers of RuboCop integration to ensure code quality:

1. **Pre-commit Hook** (Local development)
2. **GitHub Actions** (CI/CD pipeline)

## 🔨 Pre-commit Hook

Located at `.git/hooks/pre-commit`, this hook runs automatically before each commit.

### Features:
- Only checks staged Ruby files
- Auto-corrects safe violations
- Re-stages corrected files
- Clear feedback with emojis

### Usage:
```bash
# Hook is already installed and executable
# To disable temporarily:
git commit --no-verify -m "your message"

# To reinstall if needed:
chmod +x .git/hooks/pre-commit
```

## 🚀 GitHub Actions

We have three workflow options for RuboCop in CI:

### 1. **CI Workflow** (`.github/workflows/ci.yml`)
- **Purpose**: Part of the main CI pipeline
- **When**: On all pushes to main and pull requests
- **Features**:
  - Basic RuboCop check
  - GitHub annotations format
  - Fails on any error-level violations

### 2. **Comprehensive RuboCop Workflow** (`.github/workflows/rubocop.yml`)
- **Purpose**: Advanced RuboCop analysis with auto-fix capabilities
- **When**: On pull requests and pushes to main/develop
- **Features**:
  - Only checks changed files in PRs
  - Caches RuboCop results for speed
  - Checks for auto-correctable offenses
  - Posts PR comments with violation summaries
  - Can create auto-fix PRs (optional)
  - Uploads artifacts for debugging

### 3. **Simple RuboCop Workflow** (`.github/workflows/rubocop-simple.yml`)
- **Purpose**: Lightweight, straightforward RuboCop check
- **When**: On all pull requests and pushes to main
- **Features**:
  - Simple pass/fail
  - Clear error messages
  - Instructions for local fixes

## 📝 Configuration

### RuboCop Configuration (`.rubocop.yml`)
```yaml
# Using Rails Omakase standards
inherit_gem: { rubocop-rails-omakase: rubocop.yml }

# Add custom rules here if needed
```

### Choosing a Workflow

**Use the CI workflow if:**
- You want RuboCop as part of your existing CI pipeline
- You prefer a simple pass/fail check

**Use the comprehensive workflow if:**
- You want detailed PR feedback
- You need auto-fix capabilities
- You want to check only changed files in PRs
- You need caching for large codebases

**Use the simple workflow if:**
- You want a standalone RuboCop check
- You prefer minimal configuration
- You don't need advanced features

## 🛠 Common Commands

```bash
# Run RuboCop locally
bin/rubocop

# Auto-fix safe violations
bin/rubocop -a

# Auto-fix all violations (including unsafe)
bin/rubocop -A

# Check specific files
bin/rubocop app/controllers/

# Generate a TODO file for gradual fixes
bin/rubocop --auto-gen-config

# Run with GitHub annotations format (for CI)
bin/rubocop -f github
```

## ⚙️ Workflow Management

### Enable/Disable Workflows

To use only one RuboCop workflow, you can:

1. **Keep only the CI workflow**: Delete `rubocop.yml` and `rubocop-simple.yml`
2. **Use comprehensive workflow**: Delete `rubocop-simple.yml`, keep `rubocop.yml`
3. **Use simple workflow**: Delete `rubocop.yml`, keep `rubocop-simple.yml`

### Customization

Each workflow can be customized by editing the respective YAML file:
- Adjust Ruby version
- Change trigger conditions
- Modify RuboCop flags
- Add or remove features

## 🔧 Troubleshooting

### Pre-commit Hook Issues

If the pre-commit hook isn't working:
```bash
# Check if it's executable
ls -la .git/hooks/pre-commit

# Make it executable
chmod +x .git/hooks/pre-commit

# Test it manually
.git/hooks/pre-commit
```

### GitHub Actions Failures

1. **Check Ruby version**: Ensure `.ruby-version` matches your Gemfile
2. **Bundle issues**: Clear cache in GitHub Actions settings
3. **RuboCop version**: Ensure `Gemfile.lock` has compatible versions

### Local RuboCop Issues

```bash
# Update RuboCop
bundle update rubocop rubocop-rails-omakase

# Clear RuboCop cache
rm -rf ~/.cache/rubocop_cache

# Reinstall gems
bundle install
```

## 📚 Resources

- [RuboCop Documentation](https://docs.rubocop.org/)
- [Rails Omakase](https://github.com/rails/rubocop-rails-omakase)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Pre-commit Hooks](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
