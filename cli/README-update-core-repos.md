# Core Repos Updater

A utility script that pulls the latest changes from `master` branch for all Core Service repositories and optionally rebases specific repositories.

## Quick Start

```bash
# Update all Core Service repos
pru

# Update with branch switch confirmation
pru -a

# Show help
pru -h
```

## Features

- Updates all Core Service repositories (LHSS, CHSS, LSS, AHSS)
- Automatically pulls latest changes from master
- Selectively rebases specific branches based on config file
- Option to stay on master branch after update

## Configuration

### Rebase File

Create a file at `~/code/to-rebase.txt` with branches to rebase:

```
# Branch names to rebase (one per line)
feature/SI-1234                                     # Any repo with this branch
loan-hardship-servicing-srvc:feature/SI-5678        # Specific repo:branch
# develop                                           # commented = skipped
```

### Script Configuration

Edit these variables at the top of the script:

```bash
# Projects directory
PROJECTS_DIR="$HOME/code"

# Base branch to pull from
BASE_BRANCH="master"

# Ask before switching back (default: false)
ASK_BEFORE_SWITCH="false"
```

## Usage Options

```
pru [OPTIONS] [REBASE_FILE]

Options:
  -a, --ask     Ask before switching back to original branch
  -h, --help    Display this help message
```

## Output

The script provides color-coded output showing:
- Which repositories were processed
- Rebase status (success or conflicts)
- Summary of all operations