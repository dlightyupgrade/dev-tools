#!/bin/bash
set -euo pipefail

#===============================================================
# CONFIGURATION & CONSTANTS
#===============================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="3.0.3"
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
            
            # Check if branch exists and rebase
            if git show-ref --verify --quiet refs/heads/"$branch" 2>/dev/null; then
                [[ "$VERBOSE" == "true" ]] && printf "  Rebasing %s on %s...\n" "$branch" "$BASE_BRANCH"
                if git checkout "$branch" --quiet 2>/dev/null && 
                   git rebase "$BASE_BRANCH" --quiet 2>/dev/null; then
                    
                    # Handle push if enabled
                    if [[ "$FORCE_PUSH" == "true" ]]; then
                        [[ "$VERBOSE" == "true" ]] && printf "  Pushing %s to origin...\n" "$branch"
                        if git push origin "$branch" --force --quiet 2>/dev/null; then
                            success_branches+=("$branch")
                            [[ "$VERBOSE" == "true" ]] && printf "  ✓ Successfully rebased and pushed %s\n" "$branch"
                        else
                            success_branches+=("$branch(push-failed)")
                            [[ "$VERBOSE" == "true" ]] && printf "  ✓ Rebased %s but push failed\n" "$branch"
                        fi
                    else
                        success_branches+=("$branch")
                        [[ "$VERBOSE" == "true" ]] && printf "  ✓ Successfully rebased %s\n" "$branch"
                    fi
                else
                    git rebase --abort --quiet 2>/dev/null || true
                    failed_branches+=("$branch")
                    [[ "$VERBOSE" == "true" ]] && printf "  ✗ Failed to rebase %s (conflicts)\n" "$branch"
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
    
    # Load branches to rebase
    load_branches_for_repo "$REBASE_FILE" "$repo_name" "$branches_file"
    
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
    -v, --verbose       Enable verbose output with debug information
    -g, --generate      Generate example configuration files and exit
    -h, --help          Show this help message
    --version           Show version information

CONFIGURATION:
    Config file format: One repository path per line
    Rebase file format: One branch name per line, or 'repo:branch'

EXAMPLES:
    update-core-repos.sh                    # Use default configuration
    update-core-repos.sh -v                # Run with verbose output
    update-core-repos.sh --generate         # Create example configuration files
    update-core-repos.sh custom-repos.txt  # Use custom repository list

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