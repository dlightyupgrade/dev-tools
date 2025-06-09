#!/bin/bash

# prr-claude - PR Review data extraction for Claude processing
# Usage: prr-claude [--output-file daily_note.md]
# Purpose: Designed for Claude to process PR data and generate intelligent categorization
#
# CLAUDE WORKFLOW INTEGRATION:
# This script is designed to be used with Claude Code in morning workflow or standalone PR review.
# When a user runs this script or morning workflow includes it, Claude should:
# 1. Extract raw PR data using reliable bash/gh commands  
# 2. Process the data using intelligent LLM-based categorization
# 3. Generate actionable PR report with smart groupings
# 4. Optionally update daily note with structured results
#
# This follows the same hybrid pattern as deployment-diff-claude:
# - Bash handles data extraction mechanics
# - Claude handles intelligent parsing and categorization
# - Output is both machine-readable and human-actionable

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$HOME/code"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
VERBOSE=false
OUTPUT_FILE=""

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "[DEBUG] $*" >&2
    fi
}

die() {
    log_error "$1"
    exit "${2:-1}"
}

# Check prerequisites
check_prerequisites() {
    command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is not installed. Install with: brew install gh"
    command -v jq >/dev/null 2>&1 || die "jq is not installed. Install with: brew install jq"
    
    if ! gh auth status >/dev/null 2>&1; then
        die "GitHub CLI is not authenticated. Run: gh auth login"
    fi
}

# Find config file for repositories
find_config_file() {
    local configs=(
        "$HOME/.config/dev-tools/project-list.txt"
        "$PROJECT_DIR/project-list.txt"
        "$SCRIPT_DIR/project-list.txt"
    )
    
    for config in "${configs[@]}"; do
        if [[ -f "$config" && -r "$config" ]]; then
            if grep -v '^[[:space:]]*#' "$config" | grep -q '[^[:space:]]'; then
                echo "$config"
                return 0
            fi
        fi
    done
    
    die "No valid config file found. Please create project-list.txt with repository paths."
}

# Load repositories from config
load_repositories() {
    local config_file="$1"
    local -a repo_paths=()
    local -a repo_names=()
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        line=$(echo "$line" | xargs)
        [[ -z "$line" ]] && continue
        
        if [[ "$line" == /* ]]; then
            repo_paths+=("$line")
            repo_names+=("$(basename "$line")")
        else
            repo_paths+=("$PROJECT_DIR/$line")
            repo_names+=("$line")
        fi
    done < "$config_file"
    
    echo "${repo_paths[@]}"
}

# Get repository GitHub info
get_repo_info() {
    local repo_path="$1"
    
    if ! cd "$repo_path" 2>/dev/null || [[ ! -d ".git" ]]; then
        return 1
    fi
    
    local repo_url
    repo_url=$(git config --get remote.origin.url 2>/dev/null) || return 1
    
    local owner repo
    owner=$(echo "$repo_url" | sed -E 's/.*github.com[:\/]([^\/]+)\/([^\/]+)(\.git)?$/\1/')
    repo=$(echo "$repo_url" | sed -E 's/.*github.com[:\/]([^\/]+)\/([^\/]+)(\.git)?$/\2/')
    repo=${repo%.git}
    
    echo "$owner/$repo"
}

# Extract comprehensive PR data
extract_pr_data() {
    local repo_path="$1"
    local repo_name="$2"
    
    if ! cd "$repo_path" 2>/dev/null || [[ ! -d ".git" ]]; then
        return 1
    fi
    
    local repo_info
    repo_info=$(get_repo_info "$repo_path") || return 1
    
    log_debug "Extracting PR data from $repo_name ($repo_info)"
    
    # Get comprehensive PR data
    local prs_json
    prs_json=$(gh pr list --author "@me" --json number,title,headRefName,isDraft,mergeable,reviewDecision,labels,comments,statusCheckRollup,reviewThreads,author,createdAt,updatedAt 2>/dev/null) || {
        log_warn "Failed to fetch PRs for $repo_name"
        return 1
    }
    
    local pr_count
    pr_count=$(echo "$prs_json" | jq 'length')
    
    if [[ "$pr_count" -gt 0 ]]; then
        echo "=== REPOSITORY: $repo_name ==="
        echo "GitHub: $repo_info"
        echo "PR Count: $pr_count"
        echo ""
        
        # Process each PR with enhanced data
        echo "$prs_json" | jq -c '.[]' | while read -r pr_data; do
            echo "--- PR DATA ---"
            echo "$pr_data" | jq .
            echo ""
        done
    fi
}

# Main extraction function
main() {
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -o|--output-file)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Options:
    -v, --verbose          Enable verbose output
    -o, --output-file     Specify output file (e.g., daily note)
    -h, --help            Show this help message

Purpose: Extract PR data for Claude intelligent processing

CLAUDE WORKFLOW INTEGRATION:
This script follows the hybrid pattern from deployment-diff-claude:
1. Bash extracts reliable, comprehensive PR data
2. Claude processes with intelligent categorization
3. Result: Smart PR groupings and actionable insights

Trigger phrases for Claude workflows:
- "run prr-claude" or "prr analysis"
- Morning workflow auto-execution
- Standalone PR review requests
EOF
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                die "Unexpected argument: $1"
                ;;
        esac
    done
    
    log_info "Starting PR data extraction for Claude processing..."
    
    check_prerequisites
    
    local config_file
    config_file=$(find_config_file)
    log_debug "Using config file: $config_file"
    
    local repo_paths
    repo_paths=($(load_repositories "$config_file"))
    
    echo "=== PR REVIEW DATA FOR CLAUDE ==="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Total Repositories: ${#repo_paths[@]}"
    echo "Output File: ${OUTPUT_FILE:-stdout}"
    echo ""
    
    # Extract data from each repository
    local total_prs=0
    for repo_path in "${repo_paths[@]}"; do
        local repo_name
        repo_name=$(basename "$repo_path")
        
        if extract_pr_data "$repo_path" "$repo_name"; then
            # Count PRs for this repo
            if cd "$repo_path" 2>/dev/null && [[ -d ".git" ]]; then
                local count
                count=$(gh pr list --author "@me" | wc -l 2>/dev/null || echo "0")
                total_prs=$((total_prs + count))
            fi
        fi
    done
    
    echo "=== EXTRACTION SUMMARY ==="
    echo "Total PRs Found: $total_prs"
    echo "Repositories Processed: ${#repo_paths[@]}"
    echo ""
    
    # Claude processing instructions
    echo "--- CLAUDE PROCESSING INSTRUCTIONS ---"
    cat << 'EOF'
Based on the PR data above, please create an intelligent PR review report with the following requirements:

1. **Smart Categorization Logic**:
   - "Ready for Merge": No real blockers (draft=false, no conflicts, passing checks, no unresolved comments, no changes requested)
   - "Good Standing" (or "Ready for Approval"): Only has "DO NOT MERGE" label with no other issues - this is actually positive!
   - "Needs Attention": Has real blockers (conflicts, failing checks, unresolved comments, changes requested, other blocking labels)
   - "Quick Fix Priority": PRs with "quick-fix" in branch name get special treatment

2. **Enhanced Analysis**:
   - Check if "DO NOT MERGE" is the ONLY issue - if so, categorize as good standing
   - Identify truly blocking issues vs process labels
   - Consider PR age (older PRs may need more attention)
   - Look for patterns in failing checks or common issues

3. **Actionable Grouping**:
   ```
   ## PR Review Analysis
   
   > Updated: [timestamp] | Total PRs: [count]
   
   ### 🟢 Ready for Merge ([count])
   *All checks passing, no blockers*
   - [PR Title] ([URL])
   
   ### 🟡 Good Standing - Awaiting Final Approval ([count])  
   *Only "DO NOT MERGE" label present - ready for final review*
   - [PR Title] ([URL]) - Ready for approval
   
   ### 🔴 Needs Attention ([count])
   *Has blocking issues requiring action*
   - [PR Title] ([URL])
     - Issue 1, Issue 2, etc.
   
   ### ⚡ Quick Fix Priority ([count])
   *Fast-track PRs needing immediate attention*
   - [PR Title] ([URL]) - [status/issues]
   ```

4. **Smart Issue Detection**:
   - Failing CI checks (look at statusCheckRollup)
   - Merge conflicts (mergeable: "CONFLICTING")
   - Unresolved review comments (reviewThreads with isResolved: false)
   - Changes requested (reviewDecision: "CHANGES_REQUESTED")
   - Draft status (isDraft: true)
   - Blocking labels (except "DO NOT MERGE" when alone)

5. **Output Guidelines**:
   - Use the actionable grouping format above
   - Include PR URLs for easy access
   - List specific issues for "Needs Attention" PRs
   - Prioritize quick-fix PRs appropriately
   - Make it clear what action is needed for each category

Parse the JSON data intelligently and create a useful, actionable PR report that helps prioritize work effectively.
EOF
    
    echo ""
    echo "=== END PR DATA ==="
    
    log_success "PR data extraction completed. Ready for Claude processing."
}

# Run main function with all arguments
main "$@"