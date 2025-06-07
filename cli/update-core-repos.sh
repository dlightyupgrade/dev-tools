#!/bin/bash
set -euo pipefail

#===============================================================
# SCRIPT GOALS & DESIGN PRINCIPLES
#===============================================================
# PURPOSE: Safe, efficient Git repository maintenance tool for development workflows
#
# PRIMARY GOALS:
# 1. SAFETY FIRST - Never leave repositories in broken/conflicted states
# 2. EFFICIENT UPDATES - Batch update multiple repositories with master branch pulls  
# 3. SMART REBASING - Automatically rebase feature branches when safe to do so
# 4. CONFLICT AVOIDANCE - Pre-detect conflicts and skip problematic rebases
# 5. CLEAN RECOVERY - Always restore repositories to known-good states
# 6. TRANSPARENCY - Provide clear feedback on what was done and what failed
#
# CORE FEATURES:
# - Multi-repository batch processing with parallel-safe operations
# - Single target processing: process one specific repo:branch, PR URL, or branch in current repo
# - Configurable repository lists (project-list.txt) and branch lists (to-rebase.txt)  
# - GitHub URL parsing: branch URLs (tree/branch-name) and PR URLs (pull/123) with 'gh' CLI
# - Smart repository detection when running from within a git repository
# - Automatic stashing/unstashing of working directory changes
# - Pre-flight conflict detection using git merge-tree
# - Force-abort any rebase conflicts with comprehensive cleanup
# - Detailed logging and progress reporting with colored output
# - Bash 3+ compatibility for maximum system support
# - Graceful error handling with proper exit codes
#
# SAFETY GUARANTEES:
# - Always abort rebase operations that encounter conflicts
# - Multiple abort attempts with forced cleanup of git state directories
# - Reset working directory to clean state after failures  
# - Restore original branch and working changes on completion
# - Never force-push unless explicitly enabled
# - Skip rebases when master branch wasn't updated (unless forced)
#
# DESIGN PRINCIPLES:
# - Fail fast and fail safe - abort operations rather than leave broken state
# - Provide comprehensive feedback - users should understand what happened
# - Configurable behavior - support different workflows via options
# - Maintainable code - clear functions, good error handling, documented logic
# - Performance considerations - efficient git operations, minimal disk I/O
#
# REBUILD CHECKLIST (if rewriting from scratch):
# [ ] Repository discovery and validation from config files
# [ ] Single target parsing: GitHub branch/PR URLs, repo:branch format, current repo detection
# [ ] GitHub CLI integration for PR branch name extraction
# [ ] Working directory stashing with unique identifiers  
# [ ] Master branch fetching and fast-forward updates
# [ ] Conflict pre-detection using git merge-tree
# [ ] Safe rebase with immediate abort on any failure
# [ ] Force cleanup of .git/rebase-* directories
# [ ] Original state restoration (branch + stash)
# [ ] Colored progress output with verbose mode
# [ ] Proper exit codes and error aggregation
# [ ] Configuration file generation and validation
# [ ] Single vs multi-repository execution modes

#===============================================================
# CONFIGURATION & CONSTANTS
#===============================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="4.0.0"
readonly PROJECTS_DIR="$HOME/code"
readonly CONFIG_DIR="$HOME/.config/dev-tools"
readonly CONFIG_FILE_NAME="project-list.txt"
readonly REBASE_FILE_NAME="to-rebase.txt"
readonly BASE_BRANCH="master"
readonly PROTECTED_BRANCHES=("master" "main")

# Runtime settings
ASK_BEFORE_SWITCH="false"
FORCE_PUSH="true"
CLEAN_BRANCHES="true"
FORCE_REBASE="false"
VERBOSE="false"
UPDATE_TRACKING_ONLY="false"
SHOW_CLEANUP_ONLY="false"
CLEANUP_MODE="false"
DRY_RUN="false"
CONFIRM_CLEANUP="false"
DELETE_LOCAL_BRANCHES="false"
BRANCH_MODE="false"
REPO_MODE="false"

# Colors - initialize early
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# Global arrays for results (bash 3 compatible)
REPOS=()
SUCCESS_REPOS=()
FAILED_REPOS=()
REPO_RESULTS=()
REPO_NAMES=()

#===============================================================
# UTILITIES & ERROR HANDLING
#===============================================================
setup_environment() {
    # Trap for cleanup on exit
    trap cleanup_on_exit EXIT
    trap 'log_error "Interrupted by user"; exit 130' INT TERM
    
    # Create temp directory for parallel processing
    readonly TEMP_DIR="$(mktemp -d -t "${SCRIPT_NAME}.XXXXXX")"
}

cleanup_on_exit() {
    [[ -d "${TEMP_DIR:-}" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
    # Clear any background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
}

# Simple, always-visible logging
log_info() { 
    printf "%b%s%b\n" "$GREEN" "$1" "$NC"
}

log_warn() { 
    printf "%b%s%b\n" "$YELLOW" "$1" "$NC" >&2
}

log_error() { 
    printf "%b%s%b\n" "$RED" "$1" "$NC" >&2
}

log_debug() { 
    [[ "$VERBOSE" == "true" ]] && printf "%b[DEBUG] %s%b\n" "$BLUE" "$1" "$NC" >&2 || true
}

# Simple progress for default mode
show_repo_progress() {
    local current="$1" total="$2" repo_name="$3"
    printf "%b[%d/%d]%b Processing %s...\n" "$BOLD" "$current" "$total" "$NC" "$repo_name"
}

#===============================================================
# CONFIGURATION MANAGEMENT (BASH 3 COMPATIBLE)
#===============================================================
validate_config() {
    local config_file="$1"
    
    [[ ! -f "$config_file" ]] && {
        log_error "Configuration file not found: $config_file"
        log_info "Run with --generate to create example files"
        return 1
    }
    
    [[ ! -r "$config_file" ]] && {
        log_error "Cannot read configuration file: $config_file"
        return 1
    }
    
    # Check for empty config
    if ! grep -q '^[^#[:space:]]' "$config_file" 2>/dev/null; then
        log_error "Configuration file is empty or contains only comments"
        return 1
    fi
    
    return 0
}

# Load repositories - bash 3 compatible approach
load_repositories() {
    local config_file="$1"
    local invalid_count=0
    
    validate_config "$config_file" || return 1
    
    # Clear global array
    REPOS=()
    
    # Process each line
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Clean the line
        line="${line#"${line%%[![:space:]]*}"}"  # ltrim
        line="${line%"${line##*[![:space:]]}"}"  # rtrim
        
        # Resolve path
        local repo_path
        if [[ "$line" == /* ]]; then
            repo_path="$line"
        else
            repo_path="$PROJECTS_DIR/$line"
        fi
        
        # Validate repository
        if [[ -d "$repo_path" ]]; then
            if [[ -d "$repo_path/.git" ]]; then
                REPOS+=("$repo_path")
                log_debug "Added repository: $repo_path"
            else
                log_warn "Skipping $repo_path (not a git repository)"
                ((invalid_count++))
            fi
        else
            log_warn "Skipping $repo_path (directory not found)"
            ((invalid_count++))
        fi
    done < "$config_file"
    
    if [[ ${#REPOS[@]} -eq 0 ]]; then
        log_error "No valid repositories found in configuration"
        return 1
    fi
    
    [[ $invalid_count -gt 0 ]] && log_warn "Skipped $invalid_count invalid repository paths"
    log_debug "Loaded ${#REPOS[@]} valid repositories"
    return 0
}

# Load branches for a specific repository
load_branches_for_repo() {
    local rebase_file="$1"
    local repo_name="$2"
    local result_file="$3"
    
    [[ ! -f "$rebase_file" ]] && return 0
    
    # Clear result file
    > "$result_file"
    
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Handle enhanced format
        local tracking_data
        local branch
        if parse_tracking_line "$line" tracking_data; then
            branch="${tracking_data[0]}"
            local repo="${tracking_data[3]}"
            
            # Include branch if it matches this repo or is marked as "multiple"
            if [[ "$repo" == "multiple" || "$repo" == "$repo_name" ]]; then
                is_protected_branch "$branch" || echo "$branch" >> "$result_file"
            fi
        else
            # Handle legacy format and repo-specific branches
            if [[ "$line" == "$repo_name:"* ]]; then
                branch="${line#*:}"
                is_protected_branch "$branch" || echo "$branch" >> "$result_file"
            elif [[ "$line" != *":"* && "$line" != *"|"* ]]; then
                # Simple branch name (legacy format)
                is_protected_branch "$line" || echo "$line" >> "$result_file"
            fi
        fi
    done < "$rebase_file"
}

is_protected_branch() {
    local branch="$1"
    for protected in "${PROTECTED_BRANCHES[@]}"; do
        [[ "$branch" == "$protected" ]] && return 0
    done
    return 1
}

#===============================================================
# TRACKING FILE BRANCH LOOKUP
#===============================================================
# Look up branch in tracking file to find repository
lookup_branch_in_tracking() {
    local branch="$1"
    local tracking_file="$2"
    
    [[ ! -f "$tracking_file" ]] && return 1
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse the line
        local tracking_data
        if ! parse_tracking_line "$line" tracking_data; then
            continue
        fi
        
        local tracked_branch="${tracking_data[0]}"
        local repo="${tracking_data[3]}"
        
        if [[ "$tracked_branch" == "$branch" ]]; then
            echo "$repo"
            return 0
        fi
    done < "$tracking_file"
    
    return 1
}

#===============================================================
# SINGLE TARGET PROCESSING
#===============================================================
parse_single_target() {
    local target="$1"
    local repo_name="" branch_name=""
    
    # Handle explicit branch mode
    if [[ "$BRANCH_MODE" == "true" ]]; then
        branch_name="$target"
        
        # Look up branch in tracking file first
        repo_name="$(lookup_branch_in_tracking "$branch_name" "$REBASE_FILE")"
        
        if [[ -z "$repo_name" ]]; then
            # Fall back to current directory if not found in tracking
            if git rev-parse --git-dir >/dev/null 2>&1; then
                local current_repo_path
                current_repo_path="$(git rev-parse --show-toplevel 2>/dev/null)"
                repo_name="$(basename "$current_repo_path" 2>/dev/null)"
                log_debug "Branch mode: $branch_name not found in tracking, using current repo: $repo_name"
            else
                log_error "Branch '$branch_name' not found in tracking file and not in a git repository"
                log_error "Run from within a repository or ensure branch is tracked in: $REBASE_FILE"
                return 1
            fi
        else
            log_debug "Branch mode: found $branch_name in repo $repo_name via tracking file"
        fi
        
    # Handle explicit repo mode
    elif [[ "$REPO_MODE" == "true" ]]; then
        repo_name="$target"
        branch_name=""  # Will detect user branches
        log_debug "Repo mode: repo=$repo_name (will detect user branches)"
        
    # GitHub PR URL format: https://github.com/org/repo-name/pull/123
    elif [[ "$target" =~ ^https://github\.com/[^/]+/([^/]+)/pull/[0-9]+$ ]]; then
        repo_name="${BASH_REMATCH[1]}"
        
        # Use gh CLI to get the branch name
        if command -v gh >/dev/null 2>&1; then
            branch_name="$(gh pr view "$target" --json headRefName --jq '.headRefName' 2>/dev/null || echo "")"
            if [[ -z "$branch_name" ]]; then
                log_error "Failed to get branch name from PR URL: $target"
                log_error "Make sure 'gh' CLI is installed and authenticated"
                return 1
            fi
        else
            log_error "GitHub CLI (gh) is required to process PR URLs"
            log_error "Install with: brew install gh"
            return 1
        fi
        
        log_debug "Parsed PR URL: repo=$repo_name, branch=$branch_name"
        
    # GitHub branch URL format: https://github.com/org/repo-name/tree/branch-name
    elif [[ "$target" =~ ^https://github\.com/[^/]+/([^/]+)/tree/(.+)$ ]]; then
        repo_name="${BASH_REMATCH[1]}"
        branch_name="${BASH_REMATCH[2]}"
        log_debug "Parsed branch URL: repo=$repo_name, branch=$branch_name"
        
    # repo:branch format
    elif [[ "$target" == *":"* ]]; then
        repo_name="${target%:*}"
        branch_name="${target#*:}"
        log_debug "Parsed repo:branch: repo=$repo_name, branch=$branch_name"
        
    # Repository-only format (repo-name without colon) - find user branches
    elif [[ "$target" != *"/"* && "$target" != "."* ]]; then
        repo_name="$target"
        branch_name=""  # Will be detected later
        log_debug "Parsed repo-only: repo=$repo_name (will detect user branches)"
        
    # Just branch name - detect current repo
    else
        branch_name="$target"
        
        # Check if we're in a git repository
        if git rev-parse --git-dir >/dev/null 2>&1; then
            local current_repo_path
            current_repo_path="$(git rev-parse --show-toplevel 2>/dev/null)"
            repo_name="$(basename "$current_repo_path" 2>/dev/null)"
            log_debug "Detected current repo: $repo_name, branch=$branch_name"
        else
            log_error "Not in a git repository and no repo specified"
            log_error "Use format: repo:branch or run from within a repository"
            return 1
        fi
    fi
    
    # Validate we have at least repo name
    if [[ -z "$repo_name" ]]; then
        log_error "Failed to parse target: $target"
        log_error "Use format: repo:branch, repo-name, branch-name (in repo), or GitHub URL"
        return 1
    fi
    
    # Find the repository path
    local repo_path
    if [[ "$repo_name" == "." ]]; then
        # Current directory mode
        if git rev-parse --git-dir >/dev/null 2>&1; then
            repo_path="$(git rev-parse --show-toplevel 2>/dev/null)"
            repo_name="$(basename "$repo_path" 2>/dev/null)"
        else
            log_error "Current directory is not a git repository"
            return 1
        fi
    else
        repo_path="$PROJECTS_DIR/$repo_name"
    fi
    
    if [[ ! -d "$repo_path" ]]; then
        log_error "Repository not found: $repo_path"
        return 1
    fi
    
    if [[ ! -d "$repo_path/.git" ]]; then
        log_error "Not a git repository: $repo_path"
        return 1
    fi
    
    # Export for use by main processing
    SINGLE_REPO_PATH="$repo_path"
    SINGLE_BRANCH_NAME="$branch_name"
    
    return 0
}

# Detect user branches in a repository (branches that likely belong to the user)
detect_user_branches() {
    local repo_path="$1"
    local result_file="$2"
    
    cd "$repo_path" || return 1
    
    # Clear result file
    > "$result_file"
    
    # Get all local branches except protected ones
    local branches
    branches="$(git branch --format='%(refname:short)' 2>/dev/null | grep -v "^$BASE_BRANCH$" | grep -v "^main$" || echo "")"
    
    if [[ -z "$branches" ]]; then
        log_debug "No user branches found in $(basename "$repo_path")"
        return 0
    fi
    
    # Filter out remote tracking branches that aren't local feature branches
    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        
        # Skip protected branches
        is_protected_branch "$branch" && continue
        
        # Include the branch if it has local commits or matches common patterns
        local has_local_commits
        has_local_commits="$(git rev-list --count "$branch" --not origin/"$BASE_BRANCH" 2>/dev/null || echo "0")"
        
        # Include if it has local commits, or matches user branch patterns
        if [[ "$has_local_commits" -gt 0 ]] || \
           [[ "$branch" =~ ^(feature|fix|hotfix|bugfix|chore|refactor|nojira|SI-|JIRA-) ]]; then
            echo "$branch" >> "$result_file"
            log_debug "Added user branch: $branch"
        fi
    done <<< "$branches"
    
    return 0
}

#===============================================================
# ENHANCED TRACKING FUNCTIONS
#===============================================================
# Parse enhanced tracking file format
parse_tracking_line() {
    local line="$1"
    local result_var="$2"
    
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && return 1
    
    # Check if it's enhanced format (contains pipes)
    if [[ "$line" == *"|"* ]]; then
        # Enhanced format: branch|pr_url|status|repo|date|notes
        IFS='|' read -r branch pr_url status repo date notes <<< "$line"
        eval "$result_var=(\"$branch\" \"$pr_url\" \"$status\" \"$repo\" \"$date\" \"$notes\")"
    else
        # Legacy format: just branch name
        local branch="$line"
        branch="${branch#"${branch%%[![:space:]]*}"}"  # ltrim
        branch="${branch%"${branch##*[![:space:]]}"}"  # rtrim
        eval "$result_var=(\"$branch\" \"auto\" \"unknown\" \"multiple\" \"$(date +%Y-%m-%d)\" \"LEGACY\")"
    fi
    
    return 0
}

# Check PR status for a branch
check_branch_pr_status() {
    local repo_path="$1"
    local branch="$2"
    local repo_name="$(basename "$repo_path")"
    
    cd "$repo_path" || return 1
    
    # Check if branch exists locally
    if ! git show-ref --verify --quiet refs/heads/"$branch" 2>/dev/null; then
        echo "not_found"
        return 0
    fi
    
    # Check if branch is merged into master (using merge-base)
    local merge_base
    merge_base="$(git merge-base "$branch" "$BASE_BRANCH" 2>/dev/null || echo "")"
    local master_hash
    master_hash="$(git rev-parse "$BASE_BRANCH" 2>/dev/null || echo "")"
    
    if [[ -n "$merge_base" && -n "$master_hash" && "$merge_base" == "$master_hash" ]]; then
        # Branch is behind or at master - check if it has unique commits
        local branch_hash
        branch_hash="$(git rev-parse "$branch" 2>/dev/null || echo "")"
        if [[ "$branch_hash" == "$master_hash" ]]; then
            echo "merged_exact"
            return 0
        fi
        
        # Check if all branch commits are in master
        local unique_commits
        unique_commits="$(git rev-list "$branch" --not "$BASE_BRANCH" 2>/dev/null | wc -l)"
        if [[ "$unique_commits" -eq 0 ]]; then
            echo "merged"
            return 0
        fi
    fi
    
    # Check for open PR using gh CLI
    if command -v gh >/dev/null 2>&1; then
        # Try to get PR info for this branch
        local pr_info
        pr_info="$(gh pr list --head "$branch" --json state,url --jq '.[0] | "\(.state)|\(.url)"' 2>/dev/null || echo "")"
        
        if [[ -n "$pr_info" && "$pr_info" != "null|null" ]]; then
            local pr_state="${pr_info%|*}"
            case "$pr_state" in
                OPEN|open) echo "open_pr"; return 0 ;;
                MERGED|merged) echo "merged_pr"; return 0 ;;
                CLOSED|closed) echo "closed_pr"; return 0 ;;
                DRAFT|draft) echo "draft_pr"; return 0 ;;
            esac
        fi
        
        # Check for merged PRs by searching commit history
        local recent_commits
        recent_commits="$(git log --oneline -10 "$BASE_BRANCH" --grep="$branch" 2>/dev/null || echo "")"
        if [[ -n "$recent_commits" ]]; then
            echo "merged_pr"
            return 0
        fi
    fi
    
    echo "active"
    return 0
}

# Get PR details using GitHub GraphQL API
get_pr_details_from_url() {
    local pr_url="$1"
    
    if [[ -z "$pr_url" || "$pr_url" == "auto" || "$pr_url" == "none" ]]; then
        return 1
    fi
    
    # Extract PR number from URL
    if [[ "$pr_url" =~ /pull/([0-9]+)$ ]]; then
        local pr_number="${BASH_REMATCH[1]}"
        
        if command -v gh >/dev/null 2>&1; then
            # Get PR details via GraphQL
            gh pr view "$pr_number" --json headRefName,state,mergedAt --jq '. | "\(.headRefName)|\(.state)|\(.mergedAt)"' 2>/dev/null || echo ""
        else
            return 1
        fi
    else
        return 1
    fi
}

# Enhanced branch status detection using PR information
check_branch_status_enhanced() {
    local repo_path="$1"
    local branch="$2"
    local pr_url="${3:-}"
    
    cd "$repo_path" || return 1
    
    # Check if branch exists locally
    if ! git show-ref --verify --quiet refs/heads/"$branch" 2>/dev/null; then
        echo "not_found"
        return 0
    fi
    
    # If we have a PR URL, use GraphQL API for accurate status
    if [[ -n "$pr_url" && "$pr_url" != "auto" && "$pr_url" != "none" ]]; then
        local pr_details
        pr_details="$(get_pr_details_from_url "$pr_url")"
        
        if [[ -n "$pr_details" ]]; then
            local pr_branch="${pr_details%%|*}"
            local pr_state="${pr_details#*|}"
            pr_state="${pr_state%%|*}"
            local merged_at="${pr_details##*|}"
            
            # Verify branch name matches
            if [[ "$pr_branch" == "$branch" ]]; then
                case "$pr_state" in
                    MERGED|merged) 
                        echo "merged_pr"
                        return 0 ;;
                    OPEN|open) 
                        echo "open_pr"
                        return 0 ;;
                    CLOSED|closed) 
                        echo "closed_pr"
                        return 0 ;;
                    DRAFT|draft) 
                        echo "draft_pr"
                        return 0 ;;
                esac
            fi
        fi
    fi
    
    # Fall back to original logic if no PR URL or GraphQL failed
    check_branch_pr_status "$repo_path" "$branch"
}

# Auto-detect PR URL for a branch
detect_pr_url() {
    local repo_path="$1"
    local branch="$2"
    
    cd "$repo_path" || return 1
    
    if command -v gh >/dev/null 2>&1; then
        # Get PR URL if it exists
        local pr_url
        pr_url="$(gh pr list --head "$branch" --json url --jq '.[0].url' 2>/dev/null || echo "")"
        
        if [[ -n "$pr_url" && "$pr_url" != "null" ]]; then
            echo "$pr_url"
            return 0
        fi
        
        # Search in recently closed/merged PRs
        pr_url="$(gh search prs --repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" "$branch" --state=closed --json url --jq '.[0].url' 2>/dev/null || echo "")"
        
        if [[ -n "$pr_url" && "$pr_url" != "null" ]]; then
            echo "$pr_url"
            return 0
        fi
    fi
    
    echo "auto"
    return 0
}

# Update tracking file with current branch status
update_branch_tracking() {
    local tracking_file="$1"
    local repo_path="${2:-}"
    local single_branch="${3:-}"
    local known_pr_url="${4:-}"
    
    [[ ! -f "$tracking_file" ]] && return 0
    
    local updated_count=0
    
    # For single branch mode, check if branch exists in repo but not in tracking
    if [[ -n "$single_branch" && -n "$repo_path" ]]; then
        cd "$repo_path" || return 1
        
        # Check if branch exists locally
        if ! git show-ref --verify --quiet refs/heads/"$single_branch" 2>/dev/null; then
            [[ "$VERBOSE" == "true" ]] && log_info "Branch '$single_branch' not found in repository"
            return 0
        fi
        
        # Check if branch already exists in tracking file and update if needed
        local branch_exists=false
        local temp_file="${tracking_file}.update.$$"
        
        while IFS= read -r line; do
            # Copy comments and empty lines as-is
            if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
                echo "$line" >> "$temp_file"
                continue
            fi
            
            local tracking_data
            if ! parse_tracking_line "$line" tracking_data; then
                echo "$line" >> "$temp_file"
                continue
            fi
            
            local tracked_branch="${tracking_data[0]}"
            if [[ "$tracked_branch" == "$single_branch" ]]; then
                branch_exists=true
                
                # Get current tracking data
                local old_pr_url="${tracking_data[1]}"
                local old_status="${tracking_data[2]}"
                local repo="${tracking_data[3]}"
                local date="${tracking_data[4]}"
                local old_notes="${tracking_data[5]}"
                
                # Get current branch status using enhanced detection
                local pr_url="$known_pr_url"
                if [[ -z "$pr_url" ]]; then
                    pr_url="$(detect_pr_url "$repo_path" "$single_branch")"
                    [[ -z "$pr_url" ]] && pr_url="auto"
                fi
                
                local branch_status="$(check_branch_status_enhanced "$repo_path" "$single_branch" "$pr_url")"
                
                # Set status based on branch status
                local new_status="unknown"
                case "$branch_status" in
                    merged*|merged_pr) new_status="merged" ;;
                    open_pr) new_status="open" ;;
                    draft_pr) new_status="draft" ;;
                    closed_pr) new_status="closed" ;;
                    active) new_status="active" ;;
                esac
                
                # Update notes for merged branches
                local new_notes="$old_notes"
                if [[ "$new_status" == "merged" && "$old_status" != "merged" ]]; then
                    if [[ "$new_notes" != *"CLEANUP_NEEDED"* ]]; then
                        new_notes="${new_notes:+$new_notes,}CLEANUP_NEEDED"
                    fi
                fi
                
                # Use known PR URL if provided, otherwise keep existing
                local new_pr_url="$pr_url"
                if [[ "$known_pr_url" != "" ]]; then
                    new_pr_url="$known_pr_url"
                elif [[ "$old_pr_url" != "auto" ]]; then
                    new_pr_url="$old_pr_url"
                fi
                
                # Write updated line
                echo "$single_branch|$new_pr_url|$new_status|$repo|$date|$new_notes" >> "$temp_file"
                
                # Track if we actually updated something
                if [[ "$new_status" != "$old_status" || "$new_pr_url" != "$old_pr_url" || "$new_notes" != "$old_notes" ]]; then
                    ((updated_count++))
                    [[ "$VERBOSE" == "true" ]] && log_info "Updated branch '$single_branch': $old_status -> $new_status"
                else
                    [[ "$VERBOSE" == "true" ]] && log_info "Branch '$single_branch' already up to date"
                fi
            else
                # Copy other entries as-is
                echo "$line" >> "$temp_file"
            fi
        done < "$tracking_file"
        
        # If branch doesn't exist in tracking, add it
        if [[ "$branch_exists" == "false" ]]; then
            log_info "Adding missing branch '$single_branch' to tracking file"
            
            # Get repository name
            local repo_name="$(basename "$repo_path")"
            
            # Use known PR URL if provided, otherwise detect it
            local pr_url="$known_pr_url"
            if [[ -z "$pr_url" ]]; then
                pr_url="$(detect_pr_url "$repo_path" "$single_branch")"
                [[ -z "$pr_url" ]] && pr_url="auto"
            fi
            
            # Use enhanced status detection with PR information
            local branch_status="$(check_branch_status_enhanced "$repo_path" "$single_branch" "$pr_url")"
            
            # Set status based on branch status
            local status="unknown"
            case "$branch_status" in
                merged*|merged_pr) status="merged" ;;
                open_pr) status="open" ;;
                draft_pr) status="draft" ;;
                closed_pr) status="closed" ;;
                active) status="active" ;;
            esac
            
            # Add cleanup marker for merged branches
            local notes="AUTO_DETECTED"
            if [[ "$status" == "merged" ]]; then
                notes="AUTO_DETECTED,CLEANUP_NEEDED"
            fi
            
            # Add to temp file
            local current_date="$(date +%Y-%m-%d)"
            echo "$single_branch|$pr_url|$status|$repo_name|$current_date|$notes" >> "$temp_file"
            ((updated_count++))
            
            [[ "$VERBOSE" == "true" ]] && log_info "Added branch '$single_branch' with status '$status'"
        fi
        
        # Replace original file with updated temp file
        mv "$temp_file" "$tracking_file"
    fi
    
    [[ "$VERBOSE" == "true" ]] && log_info "Updated tracking info for $updated_count branches"
    
    return 0
}

# Show branches marked for cleanup
show_cleanup_candidates() {
    local tracking_file="$1"
    local filter_branch="${2:-}"
    
    [[ ! -f "$tracking_file" ]] && {
        log_error "Tracking file not found: $tracking_file"
        return 1
    }
    
    local cleanup_count=0
    local merged_count=0
    
    printf "%bBranches marked for cleanup:%b\n" "$BOLD" "$NC"
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse the line
        local tracking_data
        if ! parse_tracking_line "$line" tracking_data; then
            continue
        fi
        
        local branch="${tracking_data[0]}"
        local pr_url="${tracking_data[1]}"
        local status="${tracking_data[2]}"
        local repo="${tracking_data[3]}"
        local date="${tracking_data[4]}"
        local notes="${tracking_data[5]}"
        
        # Skip if filtering for specific branch and this isn't it
        if [[ -n "$filter_branch" && "$branch" != "$filter_branch" ]]; then
            continue
        fi
        
        # Check if marked for cleanup or merged
        if [[ "$notes" == *"CLEANUP_NEEDED"* || "$status" == "merged" ]]; then
            ((cleanup_count++))
            
            printf "  %b%s%b" "$YELLOW" "$branch" "$NC"
            [[ "$status" == "merged" ]] && printf " (%bmerged%b)" "$GREEN" "$NC" && ((merged_count++))
            [[ "$notes" == *"CLEANUP_NEEDED"* ]] && printf " (%bcleanup needed%b)" "$RED" "$NC"
            
            if [[ "$pr_url" != "auto" && "$pr_url" != "none" ]]; then
                printf " - %s" "$pr_url"
            fi
            echo
        fi
    done < "$tracking_file"
    
    if [[ $cleanup_count -eq 0 ]]; then
        log_info "No branches need cleanup"
    else
        echo
        printf "%bSummary:%b %d branches need cleanup (%d merged)\n" "$BOLD" "$NC" "$cleanup_count" "$merged_count"
        printf "Use %s--cleanup --dry-run%s to see what would be deleted\n" "$BOLD" "$NC"
        printf "Use %s--cleanup --confirm%s to perform actual cleanup\n" "$BOLD" "$NC"
    fi
    
    return 0
}

# Perform branch cleanup
cleanup_merged_branches() {
    local tracking_file="$1"
    local dry_run="${2:-false}"
    local confirm="${3:-false}"
    local filter_branch="${4:-}"
    local delete_local="${5:-false}"
    
    [[ ! -f "$tracking_file" ]] && {
        log_error "Tracking file not found: $tracking_file"
        return 1
    }
    
    # Safety check for destructive operations
    if [[ "$dry_run" == "false" && "$confirm" == "false" ]]; then
        log_error "Cleanup requires either --dry-run or --confirm flag for safety"
        log_error "Use --cleanup --dry-run to preview changes"
        log_error "Use --cleanup --confirm to perform actual cleanup"
        return 1
    fi
    
    local deleted_count=0
    local failed_count=0
    local temp_file="${tracking_file}.cleanup.$$"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would perform the following cleanup actions:"
        echo
    else
        log_info "Performing branch cleanup..."
        echo
    fi
    
    # Process tracking file
    while IFS= read -r line; do
        # Copy comments and empty lines as-is to temp file
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
            [[ "$dry_run" == "false" ]] && echo "$line" >> "$temp_file"
            continue
        fi
        
        # Parse the line
        local tracking_data
        if ! parse_tracking_line "$line" tracking_data; then
            [[ "$dry_run" == "false" ]] && echo "$line" >> "$temp_file"
            continue
        fi
        
        local branch="${tracking_data[0]}"
        local pr_url="${tracking_data[1]}"
        local status="${tracking_data[2]}"
        local repo="${tracking_data[3]}"
        local date="${tracking_data[4]}"
        local notes="${tracking_data[5]}"
        
        # Skip if filtering for specific branch and this isn't it
        if [[ -n "$filter_branch" && "$branch" != "$filter_branch" ]]; then
            [[ "$dry_run" == "false" ]] && echo "$line" >> "$temp_file"
            continue
        fi
        
        # Check if should be cleaned up
        local should_cleanup="false"
        if [[ "$notes" == *"CLEANUP_NEEDED"* || "$status" == "merged" ]]; then
            should_cleanup="true"
        fi
        
        if [[ "$should_cleanup" == "true" ]]; then
            local cleanup_success="true"
            
            if [[ "$dry_run" == "true" ]]; then
                printf "Would delete branch: %b%s%b" "$YELLOW" "$branch" "$NC"
                [[ "$pr_url" != "auto" && "$pr_url" != "none" ]] && printf " (PR: %s)" "$pr_url"
                echo
                
                # Check which repos contain this branch
                local repo_paths=()
                if [[ -n "${SINGLE_REPO_PATH:-}" ]]; then
                    # Single target mode - only check the specific repository
                    repo_paths=("$SINGLE_REPO_PATH")
                else
                    # Multi-repository mode - check all repositories
                    repo_paths=("${REPOS[@]}")
                fi
                
                for repo_path in "${repo_paths[@]}"; do
                    local repo_name="$(basename "$repo_path")"
                    cd "$repo_path" || continue
                    
                    if git show-ref --verify --quiet refs/heads/"$branch" 2>/dev/null; then
                        if [[ "$delete_local" == "true" ]]; then
                            printf "  - Would delete local branch from %s\n" "$repo_name"
                        else
                            printf "  - Would skip local branch in %s (use --delete-local to remove)\n" "$repo_name"
                        fi
                        
                        # Check if remote branch exists
                        if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
                            printf "  - Would delete remote branch from %s\n" "$repo_name"
                        fi
                    fi
                done
                echo
            else
                printf "Deleting branch: %b%s%b" "$YELLOW" "$branch" "$NC"
                [[ "$pr_url" != "auto" && "$pr_url" != "none" ]] && printf " (PR: %s)" "$pr_url"
                echo
                
                # Delete from repositories
                local repo_paths=()
                if [[ -n "${SINGLE_REPO_PATH:-}" ]]; then
                    # Single target mode - only check the specific repository
                    repo_paths=("$SINGLE_REPO_PATH")
                else
                    # Multi-repository mode - check all repositories
                    repo_paths=("${REPOS[@]}")
                fi
                
                for repo_path in "${repo_paths[@]}"; do
                    local repo_name="$(basename "$repo_path")"
                    cd "$repo_path" || continue
                    
                    if git show-ref --verify --quiet refs/heads/"$branch" 2>/dev/null; then
                        # Only delete local branches if explicitly allowed
                        if [[ "$delete_local" == "true" ]]; then
                            printf "  Deleting local branch from %s..." "$repo_name"
                            
                            # Try graceful delete first (branch is merged)
                            if git branch -d "$branch" 2>/dev/null; then
                                printf " %b✓%b\n" "$GREEN" "$NC"
                            elif git branch -D "$branch" 2>/dev/null; then
                                printf " %b✓%b (forced)\n" "$YELLOW" "$NC"
                            else
                                printf " %b✗%b (failed)\n" "$RED" "$NC"
                                cleanup_success="false"
                            fi
                        else
                            printf "  Skipping local branch in %s (use --delete-local to remove)\n" "$repo_name"
                        fi
                        
                        # Always try to delete remote branch if it exists
                        if git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
                            printf "  Deleting remote from %s..." "$repo_name"
                            if git push origin --delete "$branch" 2>/dev/null; then
                                printf " %b✓%b\n" "$GREEN" "$NC"
                            else
                                printf " %b✗%b (failed)\n" "$RED" "$NC"
                            fi
                        fi
                    fi
                done
            fi
            
            if [[ "$cleanup_success" == "true" ]]; then
                ((deleted_count++))
                # Don't add to temp file (remove from tracking)
            else
                ((failed_count++))
                # Keep in tracking file if cleanup failed
                [[ "$dry_run" == "false" ]] && echo "$line" >> "$temp_file"
            fi
        else
            # Keep branches that don't need cleanup
            [[ "$dry_run" == "false" ]] && echo "$line" >> "$temp_file"
        fi
        
    done < "$tracking_file"
    
    # Update tracking file if not dry run
    if [[ "$dry_run" == "false" ]]; then
        mv "$temp_file" "$tracking_file"
    fi
    
    # Show summary
    echo
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN Summary: Would delete $deleted_count branches"
        [[ $failed_count -gt 0 ]] && log_warn "Would fail to delete $failed_count branches"
    else
        log_info "Cleanup Summary: Deleted $deleted_count branches"
        [[ $failed_count -gt 0 ]] && log_warn "Failed to delete $failed_count branches"
    fi
    
    return 0
}

#===============================================================
# GIT OPERATIONS
#===============================================================
git_check_repo() {
    local repo_path="$1"
    local state_file="$2"
    
    cd "$repo_path" || return 1
    
    # Check git repository health
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "ERROR:Invalid git repository" > "$state_file"
        return 1
    fi
    
    # Get repository state
    local current_branch has_changes
    current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
    
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        has_changes="true"
    else
        has_changes="false"
    fi
    
    # Write state to file
    cat > "$state_file" << EOF
current_branch=$current_branch
initial_branch=$current_branch
has_changes=$has_changes
stash_created=false
master_updated=false
EOF
    
    return 0
}

git_update_repo() {
    local repo_path="$1"
    local repo_name="$2"
    local state_file="$3"
    
    cd "$repo_path" || return 1
    
    # Source state
    source "$state_file"
    
    # Handle stashing
    if [[ "$has_changes" == "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && printf "  Stashing changes in %s...\n" "$repo_name"
        local stash_message="auto-stash-pru-$(date +%s)"
        if git stash push -m "$stash_message" --include-untracked --quiet 2>/dev/null; then
            # Use a more portable approach to update the state file
            cat > "$state_file" << EOF
current_branch=$current_branch
initial_branch=$initial_branch
has_changes=$has_changes
stash_created=true
master_updated=$master_updated
EOF
            log_debug "[$repo_name] Stashed working changes"
        else
            log_warn "[$repo_name] Failed to stash changes"
            return 1
        fi
    fi
    
    # Fetch and update base branch
    [[ "$VERBOSE" == "true" ]] && printf "  Fetching %s from origin...\n" "$repo_name"
    git fetch origin --quiet --prune 2>/dev/null || {
        log_error "[$repo_name] Failed to fetch from origin"
        return 1
    }
    
    # Switch to base branch if needed
    if [[ "$current_branch" != "$BASE_BRANCH" ]]; then
        [[ "$VERBOSE" == "true" ]] && printf "  Switching to %s branch...\n" "$BASE_BRANCH"
        git checkout "$BASE_BRANCH" --quiet 2>/dev/null || {
            log_error "[$repo_name] Failed to checkout $BASE_BRANCH"
            return 1
        }
    fi
    
    # Pull latest changes
    local before_hash after_hash
    before_hash="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
    
    if git pull origin "$BASE_BRANCH" --quiet --ff-only 2>/dev/null; then
        after_hash="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
        
        if [[ "$before_hash" != "$after_hash" ]]; then
            # Update state file
            cat > "$state_file" << EOF
current_branch=$current_branch
initial_branch=$initial_branch
has_changes=$has_changes
stash_created=$stash_created
master_updated=true
EOF
            [[ "$VERBOSE" == "true" ]] && printf "  %s branch updated\n" "$BASE_BRANCH"
        else
            [[ "$VERBOSE" == "true" ]] && printf "  %s already up to date\n" "$BASE_BRANCH"
        fi
    else
        log_error "[$repo_name] Failed to update $BASE_BRANCH"
        return 1
    fi
    
    return 0
}

git_rebase_branches() {
    local repo_path="$1"
    local repo_name="$2"
    local state_file="$3"
    local branches_file="$4"
    local result_file="$5"
    
    cd "$repo_path" || return 1
    
    # Source state
    source "$state_file"
    
    # Initialize results
    local success_branches=() failed_branches=() skipped_branches=()
    
    # Process each branch
    if [[ -f "$branches_file" ]] && [[ -s "$branches_file" ]]; then
        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            
            # Skip if master wasn't updated (unless forced)
            if [[ "$master_updated" == "false" && "$FORCE_REBASE" == "false" ]]; then
                skipped_branches+=("$branch")
                continue
            fi
            
            # Check if branch exists
            if git show-ref --verify --quiet refs/heads/"$branch" 2>/dev/null; then
                # Check for potential conflicts before attempting rebase
                if ! git checkout "$branch" --quiet 2>/dev/null; then
                    skipped_branches+=("$branch(checkout-failed)")
                    [[ "$VERBOSE" == "true" ]] && printf "  • Failed to checkout %s\n" "$branch"
                    continue
                fi
                
                # Check if rebase is needed (branch is behind master)
                local branch_hash master_hash merge_base
                branch_hash="$(git rev-parse "$branch" 2>/dev/null)"
                master_hash="$(git rev-parse "$BASE_BRANCH" 2>/dev/null)"
                merge_base="$(git merge-base "$branch" "$BASE_BRANCH" 2>/dev/null)"
                
                # Skip if branch is already up to date
                if [[ "$merge_base" == "$master_hash" ]]; then
                    skipped_branches+=("$branch(up-to-date)")
                    [[ "$VERBOSE" == "true" ]] && printf "  • Skipped %s (already up to date)\n" "$branch"
                    continue
                fi
                
                # Check for conflicts using dry-run approach
                [[ "$VERBOSE" == "true" ]] && printf "  Checking conflicts for %s...\n" "$branch"
                if git merge-tree "$merge_base" "$branch" "$BASE_BRANCH" | grep -q "<<<<<<< "; then
                    failed_branches+=("$branch(conflicts-detected)")
                    printf "  ✗ Skipping %s (conflicts detected)\n" "$branch"
                    continue
                fi
                
                # Attempt rebase only if no conflicts detected
                printf "  Rebasing %s on %s...\n" "$branch" "$BASE_BRANCH"
                
                # Start rebase and immediately check for conflicts
                if git rebase "$BASE_BRANCH" --quiet 2>/dev/null; then
                    # Handle push if enabled
                    if [[ "$FORCE_PUSH" == "true" ]]; then
                        [[ "$VERBOSE" == "true" ]] && printf "  Pushing %s to origin...\n" "$branch"
                        if git push origin "$branch" --force --quiet 2>/dev/null; then
                            success_branches+=("$branch")
                            printf "  ✓ Successfully rebased and pushed %s\n" "$branch"
                        else
                            success_branches+=("$branch(push-failed)")
                            printf "  ✓ Rebased %s but push failed\n" "$branch"
                        fi
                    else
                        success_branches+=("$branch")
                        printf "  ✓ Successfully rebased %s\n" "$branch"
                    fi
                else
                    # CRITICAL: Always abort any ongoing rebase operation
                    printf "  ✗ Rebase failed for %s - aborting\n" "$branch"
                    
                    # Force abort any rebase state - multiple attempts for safety
                    git rebase --abort --quiet 2>/dev/null || true
                    sleep 0.1
                    git rebase --abort --quiet 2>/dev/null || true
                    
                    # Reset any partial changes
                    git reset --hard HEAD --quiet 2>/dev/null || true
                    
                    # Ensure we're back on master branch
                    git checkout "$BASE_BRANCH" --quiet 2>/dev/null || true
                    
                    # Verify repository is in clean state
                    if [[ -d ".git/rebase-merge" || -d ".git/rebase-apply" ]]; then
                        log_error "[$repo_name] WARNING: Repository still in rebase state after abort"
                        # Force cleanup
                        rm -rf ".git/rebase-merge" ".git/rebase-apply" 2>/dev/null || true
                    fi
                    
                    failed_branches+=("$branch(rebase-failed)")
                    printf "  ✗ Failed to rebase %s (conflicts/failure - aborted)\n" "$branch"
                fi
            else
                skipped_branches+=("$branch(not-found)")
                [[ "$VERBOSE" == "true" ]] && printf "  • Skipped %s (branch not found)\n" "$branch"
            fi
        done < "$branches_file"
    fi
    
    # Write results - handle empty arrays properly
    local success_list failed_list skipped_list
    if [[ ${#success_branches[@]} -gt 0 ]]; then
        success_list=$(IFS=,; echo "${success_branches[*]}")
    else
        success_list=""
    fi
    
    if [[ ${#failed_branches[@]} -gt 0 ]]; then
        failed_list=$(IFS=,; echo "${failed_branches[*]}")
    else
        failed_list=""
    fi
    
    if [[ ${#skipped_branches[@]} -gt 0 ]]; then
        skipped_list=$(IFS=,; echo "${skipped_branches[*]}")
    else
        skipped_list=""
    fi
    
    printf "SUCCESS:%s|FAILED:%s|SKIPPED:%s|UPDATED:%s|STASHED:%s\n" \
        "$success_list" "$failed_list" "$skipped_list" \
        "$master_updated" "$stash_created" > "$result_file"
    
    # Return failure if any branches failed
    [[ ${#failed_branches[@]} -eq 0 ]]
}

git_restore_state() {
    local repo_path="$1"
    local repo_name="$2"
    local state_file="$3"
    
    cd "$repo_path" || return 1
    
    # Source state
    source "$state_file"
    
    # Restore original branch if changed
    if [[ "$current_branch" != "$initial_branch" ]]; then
        if git checkout "$initial_branch" --quiet 2>/dev/null; then
            log_debug "[$repo_name] Restored to $initial_branch"
        else
            log_error "[$repo_name] Failed to restore original branch: $initial_branch"
        fi
    fi
    
    # Restore stashed changes
    if [[ "$stash_created" == "true" ]]; then
        if git stash pop --quiet 2>/dev/null; then
            log_debug "[$repo_name] Restored stashed changes"
        else
            log_error "[$repo_name] Failed to restore stashed changes - check manually"
        fi
    fi
}

#===============================================================
# MAIN PROCESSING
#===============================================================
process_single_repository() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"
    local work_dir="$TEMP_DIR/$repo_name"
    
    # Create working directory
    mkdir -p "$work_dir"
    
    local state_file="$work_dir/state"
    local branches_file="$work_dir/branches"
    local result_file="$work_dir/result"
    
    # Initialize and check repository
    if ! git_check_repo "$repo_path" "$state_file"; then
        echo "ERROR:Repository validation failed" > "$result_file"
        return 1
    fi
    
    # Update repository
    if ! git_update_repo "$repo_path" "$repo_name" "$state_file"; then
        echo "ERROR:Git update failed" > "$result_file"
        git_restore_state "$repo_path" "$repo_name" "$state_file"
        return 1
    fi
    
    # Load branches to rebase (skip if single target mode already created the file)
    if [[ ! -f "$branches_file" ]]; then
        load_branches_for_repo "$REBASE_FILE" "$repo_name" "$branches_file"
    fi
    
    # Rebase branches
    if ! git_rebase_branches "$repo_path" "$repo_name" "$state_file" "$branches_file" "$result_file"; then
        git_restore_state "$repo_path" "$repo_name" "$state_file"
        return 1
    fi
    
    # Restore state
    git_restore_state "$repo_path" "$repo_name" "$state_file"
    cd - >/dev/null 2>&1
    
    return 0
}

execute_single_target() {
    local repo_path="$SINGLE_REPO_PATH"
    local branch_name="$SINGLE_BRANCH_NAME"
    local repo_name="$(basename "$repo_path")"
    
    # Handle repository-only mode (find user branches)
    if [[ -z "$branch_name" ]]; then
        printf "Processing repository: %b%s%b (finding user branches)\n\n" "$BOLD" "$repo_name" "$NC"
        
        local work_dir="$TEMP_DIR/$repo_name"
        mkdir -p "$work_dir"
        local branches_file="$work_dir/branches"
        
        # Detect user branches in the repository
        if ! detect_user_branches "$repo_path" "$branches_file"; then
            log_error "Failed to detect user branches in $repo_name"
            return 1
        fi
        
        local branch_count
        branch_count="$(wc -l < "$branches_file" 2>/dev/null || echo "0")"
        
        if [[ "$branch_count" -eq 0 ]]; then
            log_info "No user branches found in $repo_name"
            return 0
        fi
        
        printf "Found %d user branch(es) to process:\n" "$branch_count"
        while IFS= read -r branch; do
            [[ -n "$branch" ]] && printf "  • %s\n" "$branch"
        done < "$branches_file"
        echo
        
    else
        printf "Processing single target: %b%s%b:%b%s%b\n\n" "$BOLD" "$repo_name" "$NC" "$BOLD" "$branch_name" "$NC"
        
        # Create temp branches file with just our target branch
        local work_dir="$TEMP_DIR/$repo_name"
        mkdir -p "$work_dir"
        echo "$branch_name" > "$work_dir/branches"
    fi
    
    local state_file="$work_dir/state"
    local result_file="$work_dir/result"
    
    # Update tracking information for the repository before processing
    [[ "$VERBOSE" == "true" ]] && log_info "Updating branch tracking for $repo_name..."
    if [[ -n "$branch_name" ]]; then
        # Single branch mode
        update_branch_tracking "$REBASE_FILE" "$repo_path" "$branch_name"
    else
        # Repository mode - update all branches in the branches file
        while IFS= read -r branch; do
            [[ -n "$branch" ]] && update_branch_tracking "$REBASE_FILE" "$repo_path" "$branch"
        done < "$work_dir/branches"
    fi
    
    # Process the single repository
    show_repo_progress 1 1 "$repo_name"
    
    if process_single_repository "$repo_path"; then
        printf "  %b✓%b Done\n" "$GREEN" "$NC"
        
        # Show detailed result
        if [[ -f "$result_file" ]]; then
            local result
            result="$(cat "$result_file")"
            printf "\n%bResult:%b " "$BOLD" "$NC"
            format_result "$result"
        fi
        
        # Show tracking summary for processed branches
        echo
        printf "%bTracking Summary:%b\n" "$BOLD" "$NC"
        if [[ -n "$branch_name" ]]; then
            show_branch_tracking_summary "$REBASE_FILE" "$branch_name"
        else
            while IFS= read -r branch; do
                [[ -n "$branch" ]] && show_branch_tracking_summary "$REBASE_FILE" "$branch"
            done < "$work_dir/branches"
        fi
        
        return 0
    else
        printf "  %b✗%b Failed\n" "$RED" "$NC"
        
        # Show detailed result for failures
        if [[ -f "$result_file" ]]; then
            local result
            result="$(cat "$result_file")"
            printf "\n%bResult:%b " "$BOLD" "$NC"
            format_result "$result"
        fi
        return 1
    fi
}

# Show tracking summary for a specific branch
show_branch_tracking_summary() {
    local tracking_file="$1"
    local branch="$2"
    
    [[ ! -f "$tracking_file" ]] && return 0
    
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        local tracking_data
        if ! parse_tracking_line "$line" tracking_data; then
            continue
        fi
        
        local track_branch="${tracking_data[0]}"
        local pr_url="${tracking_data[1]}"
        local status="${tracking_data[2]}"
        local notes="${tracking_data[5]}"
        
        if [[ "$track_branch" == "$branch" ]]; then
            printf "  %b%s%b: " "$BOLD" "$branch" "$NC"
            
            case "$status" in
                open) printf "%bopen PR%b" "$GREEN" "$NC" ;;
                merged) printf "%bmerged%b" "$YELLOW" "$NC" ;;
                closed) printf "%bclosed PR%b" "$RED" "$NC" ;;
                draft) printf "%bdraft PR%b" "$BLUE" "$NC" ;;
                active) printf "%bactive%b" "$GREEN" "$NC" ;;
                *) printf "%b%s%b" "$YELLOW" "$status" "$NC" ;;
            esac
            
            [[ "$pr_url" != "auto" && "$pr_url" != "none" ]] && printf " (%s)" "${pr_url#https://github.com/*/}"
            [[ "$notes" == *"CLEANUP_NEEDED"* ]] && printf " %b[cleanup needed]%b" "$RED" "$NC"
            echo
            break
        fi
    done < "$tracking_file"
}

execute_repositories() {
    local total_repos="${#REPOS[@]}"
    local completed=0
    
    printf "Processing %d repositories...\n\n" "$total_repos"
    
    # Clear global result arrays
    SUCCESS_REPOS=()
    FAILED_REPOS=()
    REPO_RESULTS=()
    REPO_NAMES=()
    
    # Process each repository
    for repo in "${REPOS[@]}"; do
        local repo_name="$(basename "$repo")"
        ((completed++))
        
        show_repo_progress "$completed" "$total_repos" "$repo_name"
        
        if process_single_repository "$repo"; then
            SUCCESS_REPOS+=("$repo_name")
            printf "  %b✓%b Done\n" "$GREEN" "$NC"
        else
            FAILED_REPOS+=("$repo_name")
            printf "  %b✗%b Failed\n" "$RED" "$NC"
        fi
        
        # Store result
        local result_file="$TEMP_DIR/$repo_name/result"
        if [[ -f "$result_file" ]]; then
            REPO_RESULTS+=("$(cat "$result_file")")
        else
            REPO_RESULTS+=("ERROR:Result file not found")
        fi
        REPO_NAMES+=("$repo_name")
        
        # Add spacing between repos unless it's the last one
        [[ $completed -lt $total_repos ]] && echo
    done
}

#===============================================================
# OUTPUT FORMATTING
#===============================================================
format_result() {
    local result="$1"
    
    if [[ "$result" == ERROR:* ]]; then
        echo "$result"
        return
    fi
    
    # Parse result components
    IFS='|' read -r success failed skipped updated stashed <<< "$result"
    
    local output="${BASE_BRANCH}"
    [[ "${updated#*:}" == "true" ]] && output+=" ✓ updated" || output+=" • up-to-date"
    [[ "${stashed#*:}" == "true" ]] && output+=", stashed"
    
    # Process branch results
    local success_list="${success#*:}"
    local failed_list="${failed#*:}"
    local skipped_list="${skipped#*:}"
    
    if [[ -n "${success_list}" ]]; then
        success_list="${success_list//,/ }"
        printf ", %b✓%b rebased: %s" "$GREEN" "$NC" "$success_list"
    fi
    
    if [[ -n "${failed_list}" ]]; then
        failed_list="${failed_list//,/ }"
        printf ", %b✗%b failed: %s" "$RED" "$NC" "$failed_list"
    fi
    
    if [[ -n "${skipped_list}" ]]; then
        skipped_list="${skipped_list//,/ }"
        printf ", %b•%b skipped: %s" "$YELLOW" "$NC" "$skipped_list"
    fi
    
    echo "$output"
}

#===============================================================
# COMMAND LINE INTERFACE
#===============================================================
show_version() {
    echo "$SCRIPT_NAME version $VERSION"
    echo "Enhanced repository updater with bash 3+ compatibility"
}

show_help() {
    cat << 'EOF'
update-core-repos.sh - Git Repository Update Tool

USAGE:
    update-core-repos.sh [OPTIONS] [CONFIG_FILE]

OPTIONS:
    -a, --ask           Ask before switching back to original branch
    -r, --rebase FILE   Specify custom rebase file
    -n, --no-push       Don't force push rebased branches to origin
    -f, --force         Force rebase even if master wasn't updated
    -s, --single TARGET Process only one branch or PR (see formats below)
    --branch BRANCH     Process single branch (looks up repo in tracking file)
    --repo REPO         Process all user branches in specified repository
    -v, --verbose       Enable verbose output with debug information
    -g, --generate      Generate example configuration files and exit
    --update-tracking   Update branch/PR status in tracking file without rebasing
    --show-cleanup      Display branches marked for cleanup
    --cleanup           Perform branch cleanup (use with --dry-run or --confirm)
    --dry-run           Show what cleanup would do without making changes
    --confirm           Confirm destructive operations (required for cleanup)
    --delete-local      Allow deletion of local branches during cleanup
    -h, --help          Show this help message
    --version           Show version information

SINGLE TARGET FORMATS:
    GitHub branch URL:  https://github.com/org/repo-name/tree/branch-name
    GitHub PR URL:      https://github.com/org/repo-name/pull/123 (extracts branch)
    repo:branch:        my-repo-name:feature-branch  
    repo only:          my-repo-name (finds all user branches in repo)
    branch only:        feature-branch (when run from repo directory)
    current dir:        . (process user branches in current repository)

CONFIGURATION:
    Config file format: One repository path per line
    Rebase file format: One branch name per line, or 'repo:branch'

EXAMPLES:
    update-core-repos.sh                    # Use default configuration
    update-core-repos.sh -v                # Run with verbose output
    update-core-repos.sh --generate         # Create example configuration files
    update-core-repos.sh custom-repos.txt  # Use custom repository list
    update-core-repos.sh --branch SI-8232_MigrateFinalPaymentReminder  # Process branch (auto-detect repo)
    update-core-repos.sh --repo loan-hardship-servicing-srvc           # Process all user branches in repo
    update-core-repos.sh -s feature-branch # Rebase single branch in current repo
    update-core-repos.sh -s repo:branch    # Rebase specific repo:branch
    update-core-repos.sh -s https://github.com/org/repo/tree/branch  # Rebase branch URL
    update-core-repos.sh -s https://github.com/org/repo/pull/123     # Rebase PR branch
    
    # Branch and PR tracking commands:
    update-core-repos.sh --update-tracking  # Update branch/PR status
    update-core-repos.sh --show-cleanup     # Show branches marked for cleanup
    update-core-repos.sh --cleanup --dry-run # Preview branch cleanup
    update-core-repos.sh --cleanup --confirm # Perform branch cleanup (remote only)
    update-core-repos.sh --cleanup --confirm --delete-local # Full cleanup including local branches
    
    # New explicit mode examples:
    update-core-repos.sh --branch my-feature-branch --cleanup --confirm  # Cleanup specific branch
    update-core-repos.sh --repo my-repo --update-tracking               # Update tracking for all repo branches  
    update-core-repos.sh --branch SI-1234-fix --show-cleanup            # Show cleanup status for branch
    
    # Single target examples (legacy):
    update-core-repos.sh -s my-repo         # Process all user branches in repo
    update-core-repos.sh -s .               # Process user branches in current repo
    update-core-repos.sh -s my-repo:branch  # Process specific branch
    update-core-repos.sh -s my-repo --update-tracking  # Update tracking for repo branches
    update-core-repos.sh -s branch --show-cleanup      # Show cleanup for single branch

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--ask) ASK_BEFORE_SWITCH="true" ;;
            -r|--rebase) 
                [[ -z "${2:-}" ]] && { log_error "Option $1 requires an argument"; exit 1; }
                REBASE_FILE_ARG="$2"; shift ;;
            -n|--no-push) FORCE_PUSH="false" ;;
            -f|--force) FORCE_REBASE="true" ;;
            -s|--single)
                [[ -z "${2:-}" ]] && { log_error "Option $1 requires an argument"; exit 1; }
                SINGLE_TARGET="$2"; shift ;;
            --branch)
                [[ -z "${2:-}" ]] && { log_error "Option $1 requires an argument"; exit 1; }
                SINGLE_TARGET="$2"; BRANCH_MODE="true"; shift ;;
            --repo)
                [[ -z "${2:-}" ]] && { log_error "Option $1 requires an argument"; exit 1; }
                SINGLE_TARGET="$2"; REPO_MODE="true"; shift ;;
            -v|--verbose) VERBOSE="true" ;;
            --update-tracking) UPDATE_TRACKING_ONLY="true" ;;
            --show-cleanup) SHOW_CLEANUP_ONLY="true" ;;
            --cleanup) CLEANUP_MODE="true" ;;
            --dry-run) DRY_RUN="true" ;;
            --confirm) CONFIRM_CLEANUP="true" ;;
            --delete-local) DELETE_LOCAL_BRANCHES="true" ;;
            -g|--generate)
                local config_file="$CONFIG_DIR/$CONFIG_FILE_NAME"
                local rebase_file="$CONFIG_DIR/$REBASE_FILE_NAME"
                mkdir -p "$CONFIG_DIR"
                
                # Create example config file
                cat > "$config_file" << 'EOF'
# Repository Update Configuration
# One repository path per line (relative to $HOME/code or absolute paths)
# Lines starting with # are comments

# Example repositories
my-project-1
my-project-2
dev-tools

# Example absolute path
# /path/to/specific/repository
EOF
                
                # Create example rebase file
                cat > "$rebase_file" << 'EOF'
# Branches to Rebase Configuration
# Format: branch-name OR repo:branch-name
# Examples:
# feature-branch                    # Rebase in all repos where it exists
# my-repo:specific-feature         # Rebase only in specific repository

# Example branches
feature-branch
hotfix-123
development
EOF
                
                log_info "Generated example configuration files:"
                log_info "  Config: $config_file"
                log_info "  Rebase: $rebase_file"
                log_info "Edit these files and run the script again"
                exit 0 ;;
            -h|--help) show_help; exit 0 ;;
            --version) show_version; exit 0 ;;
            -*) log_error "Unknown option: $1"; show_help; exit 1 ;;
            *)
                [[ -n "${CONFIG_FILE_ARG:-}" ]] && { log_error "Multiple config files specified"; exit 1; }
                CONFIG_FILE_ARG="$1" ;;
        esac
        shift
    done
}

#===============================================================
# MAIN EXECUTION
#===============================================================
main() {
    setup_environment
    parse_arguments "$@"
    
    # Set file paths early for special modes
    readonly CONFIG_FILE="${CONFIG_FILE_ARG:-$CONFIG_DIR/$CONFIG_FILE_NAME}"
    readonly REBASE_FILE="${REBASE_FILE_ARG:-$CONFIG_DIR/$REBASE_FILE_NAME}"
    
    # Handle special modes first
    if [[ "$UPDATE_TRACKING_ONLY" == "true" ]]; then
        log_debug "Update tracking mode only"
        
        # Handle single target mode for tracking updates
        if [[ -n "${SINGLE_TARGET:-}" ]]; then
            if ! parse_single_target "$SINGLE_TARGET"; then
                exit 1
            fi
            log_info "Updating tracking for single target: $(basename "$SINGLE_REPO_PATH"):$SINGLE_BRANCH_NAME"
            # Pass the original target if it was a PR URL
            local pr_url=""
            if [[ "$SINGLE_TARGET" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+$ ]]; then
                pr_url="$SINGLE_TARGET"
            fi
            update_branch_tracking "$REBASE_FILE" "$SINGLE_REPO_PATH" "$SINGLE_BRANCH_NAME" "$pr_url"
        else
            if ! load_repositories "$CONFIG_FILE"; then
                log_error "Failed to load repositories from configuration"
                exit 1
            fi
            log_info "Updating branch tracking information..."
            update_branch_tracking "$REBASE_FILE"
        fi
        log_info "Tracking update completed"
        exit 0
    fi
    
    if [[ "$SHOW_CLEANUP_ONLY" == "true" ]]; then
        log_debug "Show cleanup mode only"
        
        # Handle single branch filtering for cleanup display
        if [[ -n "${SINGLE_TARGET:-}" ]]; then
            if ! parse_single_target "$SINGLE_TARGET"; then
                exit 1
            fi
            show_cleanup_candidates "$REBASE_FILE" "$SINGLE_BRANCH_NAME"
        else
            show_cleanup_candidates "$REBASE_FILE"
        fi
        exit 0
    fi
    
    if [[ "$CLEANUP_MODE" == "true" ]]; then
        log_debug "Cleanup mode"
        
        # Handle single target mode for cleanup
        if [[ -n "${SINGLE_TARGET:-}" ]]; then
            if ! parse_single_target "$SINGLE_TARGET"; then
                exit 1
            fi
            # Single target cleanup - only affect the specified branch
            cleanup_merged_branches "$REBASE_FILE" "$DRY_RUN" "$CONFIRM_CLEANUP" "$SINGLE_BRANCH_NAME" "$DELETE_LOCAL_BRANCHES"
        else
            if ! load_repositories "$CONFIG_FILE"; then
                log_error "Failed to load repositories from configuration"
                exit 1
            fi
            cleanup_merged_branches "$REBASE_FILE" "$DRY_RUN" "$CONFIRM_CLEANUP" "" "$DELETE_LOCAL_BRANCHES"
        fi
        exit $?
    fi
    
    # Handle single target mode
    if [[ -n "${SINGLE_TARGET:-}" ]]; then
        log_debug "Single target mode: $SINGLE_TARGET"
        
        if ! parse_single_target "$SINGLE_TARGET"; then
            exit 1
        fi
        
        # Execute single target with timing
        local start_time end_time duration
        start_time="$(date +%s)"
        
        if execute_single_target; then
            end_time="$(date +%s)"
            duration="$((end_time - start_time))"
            printf "\n%b✓ Completed in %ds%b\n" "$GREEN" "$duration" "$NC"
            exit 0
        else
            end_time="$(date +%s)"
            duration="$((end_time - start_time))"
            printf "\n%b✗ Failed in %ds%b\n" "$RED" "$duration" "$NC"
            exit 1
        fi
    fi
    
    # Normal multi-repository mode
    
    log_debug "Using config file: $CONFIG_FILE"
    log_debug "Using rebase file: $REBASE_FILE"
    
    # Load repositories
    if ! load_repositories "$CONFIG_FILE"; then
        log_error "Failed to load repositories from configuration"
        exit 1
    fi
    
    # Execute repository updates with timing
    local start_time end_time duration
    start_time="$(date +%s)"
    
    # Update tracking information before processing
    [[ "$VERBOSE" == "true" ]] && log_info "Updating branch tracking information..."
    update_branch_tracking "$REBASE_FILE"
    
    execute_repositories
    
    end_time="$(date +%s)"
    duration="$((end_time - start_time))"
    
    # Generate summary
    local success_count="${#SUCCESS_REPOS[@]}"
    local failed_count="${#FAILED_REPOS[@]}"
    local total_count="$((success_count + failed_count))"
    
    printf "\n%bUPDATE SUMMARY%b\n" "$BOLD" "$NC"
    printf "Completed in %ds • " "$duration"
    
    if [[ $success_count -gt 0 ]]; then
        printf "%b%d success%b" "$GREEN" "$success_count" "$NC"
    else
        printf "%d success" "$success_count"
    fi
    
    printf " • "
    
    if [[ $failed_count -gt 0 ]]; then
        printf "%b%d failed%b" "$RED" "$failed_count" "$NC"
    else
        printf "%d failed" "$failed_count"
    fi
    
    printf " • %d total\n" "$total_count"
    
    # Show failed repositories immediately if any
    if [[ $failed_count -gt 0 ]]; then
        printf "\n%bFailed repositories:%b\n" "$RED" "$NC"
        printf '  • %s\n' "${FAILED_REPOS[@]}"
    fi
    
    # Detailed results for verbose mode or failures
    if [[ "$VERBOSE" == "true" || $failed_count -gt 0 ]]; then
        printf "\n%bDetailed Results:%b\n" "$BOLD" "$NC"
        for i in "${!REPO_NAMES[@]}"; do
            local repo_name="${REPO_NAMES[$i]}"
            printf "  %b%s%b: " "$BOLD" "$repo_name" "$NC"
            format_result "${REPO_RESULTS[$i]}"
        done
    fi
    
    # Exit with appropriate code
    [[ $failed_count -eq 0 ]]
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi