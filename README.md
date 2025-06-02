# Personal Development Tools

A collection of personal development tools and utilities for improving development workflows.

## Tools

### Claude Integration Tools

Tools that use Claude AI to enhance Git workflows and development productivity.

- `cli/claude_commit` - Generate meaningful commit messages using Claude API
- `cli/claude_branch` - Create Git branches using natural language descriptions

### Repository Management Tools

Tools for managing multiple repositories and streamlining development workflows.

- `cli/update-core-repos.sh` - Update multiple repositories, pulling latest master and rebasing branches
- `cli/review-prs-improved.sh` - Advanced PR review script with markdown reporting
- `cli/review-prs.sh` - Basic PR review and management script
- `cli/create-branch.sh` - Create new Git branches with automatic tracking configuration

[Read more about the Repo Updater](cli/README-update-core-repos.md)

### Code Quality and Analysis Tools

Tools for maintaining code quality and analyzing project health.

- `cli/check-maven-versions` - Check Maven dependencies for version updates
- `cli/check-pr-violations` - Extract and analyze CI violations from GitHub PR comments

### Utility Scripts

Supporting scripts for workflow automation.

- `cli/migrate-tracking-format.sh` - Migrate branch tracking files to enhanced format

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/dlightyupgrade/dev-tools.git personal-dev-tools
   cd personal-dev-tools
   ```

2. Add tool aliases to your .zshrc/.bashrc:
   ```bash
   # Repository Management
   alias -g pru="~/code/personal-dev-tools/cli/update-core-repos.sh"
   alias -g prr="~/code/personal-dev-tools/cli/review-prs-improved.sh"
   
   # Claude Integration
   alias -g cc="~/code/personal-dev-tools/cli/claude_commit"
   alias -g cb="~/code/personal-dev-tools/cli/claude_branch"
   
   # Code Quality
   alias -g ckver="~/code/personal-dev-tools/cli/check-maven-versions"
   alias -g check-pr-violations="~/code/personal-dev-tools/cli/check-pr-violations"
   ```

## Requirements

### Claude Integration Tools
- Git
- Python 3.6+
- Anthropic Claude API key
- `anthropic` Python package (`pip install anthropic`)

### Repository Management Tools
- Git
- GitHub CLI (`gh`) for PR management
- Bash shell

### Code Quality Tools
- Git
- GitHub CLI (`gh`) for PR data access
- Maven (for version checking tools)

## Usage Examples

### Claude Tools
```bash
# Generate a commit message with Claude
cc

# Create a branch using natural language
cb "create a branch for fixing the login bug"
```

### Repository Management
```bash
# Update all configured repositories
pru

# Generate PR status report
prr
```

### Code Quality
```bash
# Check Maven dependency versions
ckver

# Analyze PR violations with Claude integration
check-pr-violations 123 --claude
```

## Configuration

Most tools support configuration files in `~/.config/dev-tools/`. See individual tool documentation for specific configuration options.

## License

MIT