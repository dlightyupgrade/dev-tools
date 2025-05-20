# Core Repos Updater

A utility script that pulls the latest changes from `master` branch for all configured repositories and optionally rebases and force pushes specific branches.

## Quick Start

```bash
# Update all Core Service repos
pru

# Update with branch switch confirmation
pru -a

# Update but don't force push rebased branches
pru -n

# Generate example config files
pru -g

# Show help
pru -h
```

## Features

- Updates any list of repositories from a configuration file
- Automatically pulls latest changes from master branch
- Auto-stashes uncommitted changes before switching/pulling
- Selectively rebases specific branches based on config file
- Automatically force pushes successfully rebased branches
- Option to stay on master branch after update
- Detailed reporting of actions and results

## Configuration

### Repository Config File

Create a file at `~/code/repo-config.txt` with repositories to update:

```
# Repositories to update (one per line)
loan-hardship-servicing-srvc         # Relative path from ~/code
creditline-hardship-servicing-srvc
loan-servicing-srvc
actor-hardship-srvc
/path/to/another/repo                # Absolute path example
```

### Rebase File

Create a file at `~/code/to-rebase.txt` with branches to rebase:

```
# Branch names to rebase (one per line)
feature/SI-1234                                     # Any repo with this branch
loan-hardship-servicing-srvc:feature/SI-5678        # Specific repo:branch
# develop                                           # commented = skipped
# master                                            # protected branches are automatically skipped
```

### Script Configuration

Edit these variables at the top of the script to change defaults:

```bash
# Projects directory
PROJECTS_DIR="$HOME/code"
CONFIG_FILE_NAME="repo-config.txt"
REBASE_FILE_NAME="to-rebase.txt"

# Base branch to pull from (typically 'master' or 'main')
BASE_BRANCH="master"

# Set to 'true' to ask for confirmation before switching branches
ASK_BEFORE_SWITCH="false"

# Set to 'true' to force push successfully rebased branches to origin
FORCE_PUSH="true"
```

## Usage Options

```
pru [OPTIONS] [CONFIG_FILE]

Options:
  -a, --ask       Ask before switching back to original branch
  -r, --rebase    Specify a custom rebase file
  -g, --generate  Generate example config files and exit
  -n, --no-push   Don't force push rebased branches to origin
  -h, --help      Display this help message
```

## Safety Features

- Never rebases master/main branches (protected)
- Auto-stashing of uncommitted changes
- Automatic conflict detection and abort
- Rebase and push are treated as separate operations
- Clear error reporting for troubleshooting

## Output

The script provides color-coded output showing:
- Current configuration settings
- Step-by-step progress for each repository
- Auto-stash operations and status
- Rebase and push status for each branch
- Summary of successful and failed operations
- Detailed per-repository results

## Advanced Usage

### Custom Configurations

You can maintain multiple config files for different project groups:

```bash
# Use a different repo config file
pru ~/code/frontend-repos.txt

# Use a different rebase file
pru -r ~/code/urgent-branches.txt

# Combine both
pru -r ~/code/urgent-branches.txt ~/code/frontend-repos.txt
```

### CI/CD Integration

The script can be used in CI/CD pipelines:

```bash
# Non-interactive mode (always force push)
pru /path/to/ci-repos.txt

# Non-interactive mode (never force push)
pru -n /path/to/ci-repos.txt
```