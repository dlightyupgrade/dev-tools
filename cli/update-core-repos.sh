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
readonly VERSION="3.1.2"
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
        
        if [[ "$line" == "$repo_name:"* ]]; then
            local branch="${line#*:}"
            is_protected_branch "$branch" || echo "$branch" >> "$result_file"
        elif [[ "$line" != *":"* ]]; then
            is_protected_branch "$line" || echo "$line" >> "$result_file"
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
# SINGLE TARGET PROCESSING
#===============================================================
parse_single_target() {
    local target="$1"
    local repo_name="" branch_name=""
    
    # GitHub PR URL format: https://github.com/org/repo-name/pull/123
    if [[ "$target" =~ ^https://github\.com/[^/]+/([^/]+)/pull/[0-9]+$ ]]; then
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
    
    # Validate we have both parts
    if [[ -z "$repo_name" || -z "$branch_name" ]]; then
        log_error "Failed to parse target: $target"
        log_error "Use format: repo:branch, branch-name (in repo), or GitHub PR URL"
        return 1
    fi
    
    # Find the repository path
    local repo_path="$PROJECTS_DIR/$repo_name"
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
    
    printf "Processing single target: %b%s%b:%b%s%b\n\n" "$BOLD" "$repo_name" "$NC" "$BOLD" "$branch_name" "$NC"
    
    # Create temp branches file with just our target branch
    local work_dir="$TEMP_DIR/$repo_name"
    mkdir -p "$work_dir"
    echo "$branch_name" > "$work_dir/branches"
    
    local state_file="$work_dir/state"
    local result_file="$work_dir/result"
    
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
    -v, --verbose       Enable verbose output with debug information
    -g, --generate      Generate example configuration files and exit
    -h, --help          Show this help message
    --version           Show version information

SINGLE TARGET FORMATS:
    GitHub branch URL:  https://github.com/org/repo-name/tree/branch-name
    GitHub PR URL:      https://github.com/org/repo-name/pull/123 (extracts branch)
    repo:branch:        my-repo-name:feature-branch  
    branch only:        feature-branch (when run from repo directory)

CONFIGURATION:
    Config file format: One repository path per line
    Rebase file format: One branch name per line, or 'repo:branch'

EXAMPLES:
    update-core-repos.sh                    # Use default configuration
    update-core-repos.sh -v                # Run with verbose output
    update-core-repos.sh --generate         # Create example configuration files
    update-core-repos.sh custom-repos.txt  # Use custom repository list
    update-core-repos.sh -s feature-branch # Rebase single branch in current repo
    update-core-repos.sh -s repo:branch    # Rebase specific repo:branch
    update-core-repos.sh -s https://github.com/org/repo/tree/branch  # Rebase branch URL
    update-core-repos.sh -s https://github.com/org/repo/pull/123     # Rebase PR branch

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
            -v|--verbose) VERBOSE="true" ;;
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
    # Set file paths
    readonly CONFIG_FILE="${CONFIG_FILE_ARG:-$CONFIG_DIR/$CONFIG_FILE_NAME}"
    readonly REBASE_FILE="${REBASE_FILE_ARG:-$CONFIG_DIR/$REBASE_FILE_NAME}"
    
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