#!/bin/bash
set -euo pipefail

#===============================================================
# Branch Tracking Migration Utility
#===============================================================
# PURPOSE: Convert simple branch tracking files to enhanced format
# USAGE: migrate-tracking-format.sh <tracking_file>
#
# Converts from simple format:
#   branch-name-1
#   branch-name-2
#
# To enhanced format:
#   # Branch and PR Tracking System v2.0
#   branch-name-1|auto|unknown|multiple|date|AUTO_DETECTED
#   branch-name-2|auto|unknown|multiple|date|AUTO_DETECTED

readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="1.0.0"

# Colors
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

log_info() { 
    printf "%b%s%b\n" "$GREEN" "$1" "$NC"
}

log_warn() { 
    printf "%b%s%b\n" "$YELLOW" "$1" "$NC" >&2
}

log_error() { 
    printf "%b%s%b\n" "$RED" "$1" "$NC" >&2
}

show_help() {
    cat << 'EOF'
migrate-tracking-format.sh - Branch Tracking Format Migration

USAGE:
    migrate-tracking-format.sh [OPTIONS] <tracking_file>

DESCRIPTION:
    Converts simple branch tracking files to enhanced format with PR tracking.
    Creates backup of original file before migration.

OPTIONS:
    --dry-run       Show what would be migrated without making changes
    --backup-dir    Specify backup directory (default: same as source file)
    -v, --verbose   Enable verbose output
    -h, --help      Show this help message
    --version       Show version information

EXAMPLES:
    migrate-tracking-format.sh to-rebase.txt
    migrate-tracking-format.sh --dry-run ~/.config/dev-tools/to-rebase.txt
    migrate-tracking-format.sh -v --backup-dir ~/backups to-rebase.txt

FORMAT CONVERSION:
    Simple format (input):
        branch-name-1
        branch-name-2
        
    Enhanced format (output):
        # Branch and PR Tracking System v2.0
        branch-name-1|auto|unknown|multiple|2025-06-02|AUTO_DETECTED
        branch-name-2|auto|unknown|multiple|2025-06-02|AUTO_DETECTED

EOF
}

is_enhanced_format() {
    local file="$1"
    [[ -f "$file" ]] && head -1 "$file" | grep -q "Branch and PR Tracking System"
}

detect_pr_for_branch() {
    local branch="$1"
    local verbose="$2"
    
    # Try to detect PR using gh CLI if available
    if command -v gh >/dev/null 2>&1; then
        [[ "$verbose" == "true" ]] && printf "  Checking for PR: %s..." "$branch"
        
        # Search for PR with this branch name across accessible repos
        local pr_url
        pr_url="$(gh search prs --state=open "$branch" --json url --jq '.[0].url' 2>/dev/null || echo "")"
        
        if [[ -n "$pr_url" ]]; then
            [[ "$verbose" == "true" ]] && printf " found: %s\n" "$pr_url"
            echo "$pr_url|open"
        else
            # Check for closed/merged PRs
            pr_url="$(gh search prs --state=closed "$branch" --json url,state --jq '.[0] | "\(.url)|\(.state)"' 2>/dev/null || echo "")"
            if [[ -n "$pr_url" ]]; then
                [[ "$verbose" == "true" ]] && printf " found closed: %s\n" "${pr_url%|*}"
                echo "$pr_url"
            else
                [[ "$verbose" == "true" ]] && printf " not found\n"
                echo "auto|unknown"
            fi
        fi
    else
        echo "auto|unknown"
    fi
}

migrate_tracking_file() {
    local source_file="$1"
    local backup_dir="${2:-$(dirname "$source_file")}"
    local dry_run="${3:-false}"
    local verbose="${4:-false}"
    
    # Validate source file
    if [[ ! -f "$source_file" ]]; then
        log_error "Source file not found: $source_file"
        return 1
    fi
    
    if [[ ! -r "$source_file" ]]; then
        log_error "Cannot read source file: $source_file"
        return 1
    fi
    
    # Check if already enhanced format
    if is_enhanced_format "$source_file"; then
        log_warn "File is already in enhanced format: $source_file"
        return 0
    fi
    
    # Prepare backup
    local backup_file="$backup_dir/$(basename "$source_file").backup.$(date +%Y%m%d-%H%M%S)"
    local temp_file="${source_file}.tmp"
    local current_date="$(date +%Y-%m-%d)"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would migrate $source_file"
        log_info "Would create backup: $backup_file"
        echo
    else
        # Create backup directory if it doesn't exist
        mkdir -p "$backup_dir"
        
        # Create backup
        cp "$source_file" "$backup_file"
        log_info "Created backup: $backup_file"
    fi
    
    # Start building new format
    local header='# Branch and PR Tracking System v2.0
# Format: branch_name|pr_url|status|repo|created_date|notes
# 
# Status values:
#   open      - Branch has open PR
#   merged    - Branch/PR has been merged
#   closed    - PR was closed without merging
#   draft     - PR is in draft state
#   unknown   - Status needs to be determined
#
# PR URL values:
#   auto      - Auto-detect PR URL using gh CLI
#   URL       - Specific GitHub PR URL
#   none      - No PR associated
#
# Notes:
#   CLEANUP_NEEDED - Branch is merged and should be deleted
#   AUTO_DETECTED  - Entry was automatically created
#   MANUAL         - Entry was manually added
#
# Legacy format (backward compatible): just branch names on individual lines
#'
    
    if [[ "$dry_run" == "true" ]]; then
        echo "DRY RUN OUTPUT:"
        echo "$header"
        echo
    else
        echo "$header" > "$temp_file"
        echo >> "$temp_file"
    fi
    
    local processed_count=0
    local skipped_count=0
    
    # Process each line from source file
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
            ((skipped_count++))
            continue
        fi
        
        # Clean the line
        line="${line#"${line%%[![:space:]]*}"}"  # ltrim
        line="${line%"${line##*[![:space:]]}"}"  # rtrim
        
        # Skip if already enhanced format (shouldn't happen, but safety check)
        if [[ "$line" == *"|"* ]]; then
            if [[ "$dry_run" == "true" ]]; then
                echo "$line"
            else
                echo "$line" >> "$temp_file"
            fi
            continue
        fi
        
        # Detect PR information
        [[ "$verbose" == "true" ]] && printf "Processing branch: %s\n" "$line"
        
        local pr_info
        pr_info="$(detect_pr_for_branch "$line" "$verbose")"
        local pr_url="${pr_info%|*}"
        local status="${pr_info#*|}"
        
        # Create enhanced entry
        local enhanced_line="$line|$pr_url|$status|multiple|$current_date|AUTO_DETECTED"
        
        if [[ "$dry_run" == "true" ]]; then
            echo "$enhanced_line"
        else
            echo "$enhanced_line" >> "$temp_file"
        fi
        
        ((processed_count++))
        
    done < "$source_file"
    
    if [[ "$dry_run" == "false" ]]; then
        # Replace original file
        mv "$temp_file" "$source_file"
        log_info "Migration completed successfully"
    fi
    
    # Show summary
    echo
    log_info "Migration Summary:"
    printf "  Processed branches: %d\n" "$processed_count"
    printf "  Skipped lines: %d\n" "$skipped_count"
    [[ "$dry_run" == "false" ]] && printf "  Backup location: %s\n" "$backup_file"
    
    return 0
}

main() {
    local source_file=""
    local backup_dir=""
    local dry_run="false"
    local verbose="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run="true" ;;
            --backup-dir)
                [[ -z "${2:-}" ]] && { log_error "Option $1 requires an argument"; exit 1; }
                backup_dir="$2"; shift ;;
            -v|--verbose) verbose="true" ;;
            -h|--help) show_help; exit 0 ;;
            --version) echo "$SCRIPT_NAME version $VERSION"; exit 0 ;;
            -*) log_error "Unknown option: $1"; show_help; exit 1 ;;
            *)
                [[ -n "$source_file" ]] && { log_error "Multiple files specified"; exit 1; }
                source_file="$1" ;;
        esac
        shift
    done
    
    # Validate arguments
    if [[ -z "$source_file" ]]; then
        log_error "No tracking file specified"
        show_help
        exit 1
    fi
    
    # Set default backup directory
    [[ -z "$backup_dir" ]] && backup_dir="$(dirname "$source_file")"
    
    # Perform migration
    migrate_tracking_file "$source_file" "$backup_dir" "$dry_run" "$verbose"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi