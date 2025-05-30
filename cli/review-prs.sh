#!/bin/bash
# PR Review Script
# Creates a markdown report of open PRs categorized by status
#
# Usage: review-prs.sh [template_file]
#
# DAILY NOTE REQUIREMENTS:
# The daily note must have:
# 1. A main header: "# Daily Notes" (preserves everything from line 1 to this header)
# 2. A separator: "--- 📋 PR Review End ---" (preserves everything after this separator)
#
# The script will overwrite content between these two markers with fresh PR data.
# Everything above the header and below the separator is preserved.
#
# TEMPLATE FILE (optional):
# The template_file should contain a "--- 📋 PR Review End ---" separator
# to indicate where the script should stop extracting template content.
# Everything from the separator onward will be included after the PR review section.
#
# Uses GitHub CLI to fetch detailed PR information including:
# - Pull request review status
# - Status check results
# - PR comments and review threads
# - Mergeable status
#
# NOTE: This script requires gh (GitHub CLI) to be installed and authenticated
# You can install it with:
#   brew install gh
# And authenticate with:
#   gh auth login

# Get directory paths
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$HOME/code"

# Get template file from argument
TEMPLATE_FILE="$1"

# Date variables
TODAY=$(date +"%Y-%m-%d")
YEAR=$(date +"%Y")
MONTH=$(date +"%m")
MONTH_NAME=$(date +"%b")
MONTH_FULL=$(date +"%B")
DAY=$(date +"%d" | sed 's/^0//')  # Remove leading zero from day

# Note paths
DAILY_NOTE_DIR="$HOME/notes/daily/$YEAR/$MONTH-$MONTH_NAME"
DAILY_NOTE="$DAILY_NOTE_DIR/$TODAY.md"

# Config file options
CONFIG_DIR="$HOME/.config/dev-tools"
CONFIGS=(
  "$CONFIG_DIR/project-list.txt"
  "$PROJECT_DIR/project-list.txt"
  "$DIR/project-list.txt"
)

# Create daily notes directory structure if needed
mkdir -p "$DAILY_NOTE_DIR"

# Check if daily note exists
if [ ! -f "$DAILY_NOTE" ]; then
  echo "Daily note not found at $DAILY_NOTE. Will only output PR summary."
  # Set DAILY_NOTE to empty to indicate we don't want to update it
  DAILY_NOTE=""
fi

# Find a valid config file
CONFIG_FILE=""
for candidate in "${CONFIGS[@]}"; do
  if [ -f "$candidate" ]; then
    CONFIG_FILE="$candidate"
    echo "Using config file: $CONFIG_FILE"
    break
  fi
done

# Exit if no config file found
if [ -z "$CONFIG_FILE" ]; then
  echo "Error: No config file found. Looked in:"
  for candidate in "${CONFIGS[@]}"; do
    echo "  - $candidate"
  done
  echo "Please create a config file with repository paths, one per line."
  echo "Example:"
  echo "example-repo-1"
  echo "example-repo-2"
  exit 1
fi

# Load repositories from config file
REPO_PATHS=()
REPO_NAMES=()

while IFS= read -r line || [ -n "$line" ]; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  
  # Strip leading/trailing whitespace
  line=$(echo "$line" | xargs)
  
  # If line starts with '/', it's an absolute path
  # Otherwise, prepend the projects directory
  if [[ "$line" == /* ]]; then
    REPO_PATHS+=("$line")
    REPO_NAMES+=($(basename "$line"))
  else
    REPO_PATHS+=("$PROJECT_DIR/$line")
    REPO_NAMES+=("$line")
  fi
done < "$CONFIG_FILE"

# If no repositories found, display error and exit
if [ ${#REPO_PATHS[@]} -eq 0 ]; then
  echo "Error: No repositories specified in $CONFIG_FILE."
  echo "Please add at least one repository path to the config file."
  exit 1
fi

# Create temporary files for PR lists
READY_FILE=$(mktemp)
NEEDS_ATTENTION_FILE=$(mktemp)
OTHER_FILE=$(mktemp)
QUICK_FIX_READY_FILE=$(mktemp)
QUICK_FIX_ATTENTION_FILE=$(mktemp)

# Create temporary directory for working files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR" "$READY_FILE" "$NEEDS_ATTENTION_FILE" "$OTHER_FILE" "$QUICK_FIX_READY_FILE" "$QUICK_FIX_ATTENTION_FILE"' EXIT

# Process each repository
for i in "${!REPO_PATHS[@]}"; do
  REPO_PATH="${REPO_PATHS[$i]}"
  REPO_NAME="${REPO_NAMES[$i]}"
  
  echo "Checking $REPO_NAME..."
  
  if ! cd "$REPO_PATH"; then
    echo "Error: Could not change to directory $REPO_PATH"
    continue
  fi
  
  # Get PRs authored by me
  echo "  Running: gh pr list --author \"@me\""
  gh pr list --author "@me" | while read -r PR_LINE; do
    PR_NUM=$(echo "$PR_LINE" | awk '{print $1}')
    PR_TITLE=$(echo "$PR_LINE" | cut -c 8-)
    
    echo "  Processing PR #$PR_NUM (authored by me): $PR_TITLE"
    
    # Get repo owner and name from git config
    REPO_URL=$(git config --get remote.origin.url)
    OWNER=$(echo "$REPO_URL" | sed -E 's/.*github.com[:\/]([^\/]+)\/([^\/]+)(\.git)?$/\1/')
    REPO=$(echo "$REPO_URL" | sed -E 's/.*github.com[:\/]([^\/]+)\/([^\/]+)(\.git)?$/\2/')
    CLEAN_REPO=${REPO%.git}
    
    # Standard URL pattern
    URL="https://github.com/$OWNER/$CLEAN_REPO/pull/$PR_NUM"
    # Fix the URL by removing .git if present
    URL=${URL/.git\//\/}
    
    # Try to get PR data using GitHub CLI
    echo "    Fetching detailed PR data for PR #$PR_NUM"
    
    # Get title and clean it up
    PR_TITLE_CLEAN="$PR_TITLE"
    
    # The PR line format from gh is: "NUM\tTITLE\tBRANCH\tSTATUS\tDATE"
    # For now just initialize with branch name (field 3) as a backup
    PR_BRANCH=$(echo "$PR_TITLE" | cut -f3)
    
    # We'll fetch the actual title from the GitHub API later
    # In the meantime, use title from gh pr list (field 2)
    PR_TITLE_CLEAN=$(echo "$PR_TITLE" | cut -f2)
    
    # If extraction failed, use a fallback
    if [ -z "$PR_TITLE_CLEAN" ] || [ "$PR_TITLE_CLEAN" = "$PR_TITLE" ]; then
      # Try another approach - just use the first 60 chars of the PR_TITLE directly
      PR_TITLE_CLEAN=$(echo "$PR_TITLE" | cut -c 1-60)
      # If still empty, use a generic title
      if [ -z "$PR_TITLE_CLEAN" ]; then
        PR_TITLE_CLEAN="PR #$PR_NUM"
      fi
    fi
    
    # Use direct gh commands to check the status of each PR
    
    # Check if it's a draft PR
    echo "    Checking if draft PR..."
    DRAFT_CHECK=$(gh pr view "$PR_NUM" --json isDraft 2>/dev/null)
    IS_DRAFT=$(echo "$DRAFT_CHECK" | jq -r '.isDraft // false')
    [ -z "$IS_DRAFT" ] && IS_DRAFT="false"
    
    # Check if it has failing checks using status API - more reliable
    echo "    Checking CI status..."
    CHECK_STATUS=$(gh pr view "$PR_NUM" --json statusCheckRollup 2>/dev/null)
    
    # Default to passing if we can't determine (avoid false positives)
    FAILING_CHECKS=0
    
    if [ -n "$CHECK_STATUS" ]; then
      # Check if any status has conclusion != "SUCCESS" and != null and != "NEUTRAL"
      FAILURE_COUNT=$(echo "$CHECK_STATUS" | jq '.statusCheckRollup | length as $total | if $total > 0 then [.statusCheckRollup[] | select(.conclusion != "SUCCESS" and .conclusion != null and .conclusion != "NEUTRAL")] | length else 0 end' 2>/dev/null)
      
      # If jq call failed or gave empty result, try a simpler approach
      if [ -z "$FAILURE_COUNT" ] || [ "$FAILURE_COUNT" = "null" ]; then
        echo "    Failed to parse status check data, falling back to command line output"
        # Try the command line directly with specific output checking
        CI_OUTPUT=$(gh pr checks "$PR_NUM" 2>/dev/null)
        # Only look for the exact word "fail" at beginning of a column
        if echo "$CI_OUTPUT" | grep -E "^[^	]+	fail" > /dev/null; then
          FAILING_CHECKS=1
          echo "    Found failing checks in command output"
        elif echo "$CI_OUTPUT" | grep -E "^[^	]+	error" > /dev/null; then
          # Sometimes errors are reported differently
          FAILING_CHECKS=1
          echo "    Found error checks in command output"
        else
          echo "    No failing checks found, CI is passing"
        fi
      else
        # We successfully parsed the JSON output
        if [ "$FAILURE_COUNT" -gt 0 ]; then
          FAILING_CHECKS=1
          echo "    Found $FAILURE_COUNT failing checks"
        else
          echo "    All checks passing"
        fi
      fi
    else
      echo "    Failed to retrieve check status, assuming passing"
    fi
    
    # Check if it has merge conflicts 
    echo "    Checking mergeable status..."
    MERGE_STATUS=$(gh pr view "$PR_NUM" --json mergeable 2>/dev/null)
    MERGEABLE=$(echo "$MERGE_STATUS" | jq -r '.mergeable // "UNKNOWN"')
    [ -z "$MERGEABLE" ] && MERGEABLE="UNKNOWN"
    
    # Check for unresolved comments
    echo "    Checking for unresolved comments..."
    REVIEW_COMMENTS=$(gh pr view "$PR_NUM" --json comments,reviewThreads 2>/dev/null)
    COMMENT_COUNT=0
    if [ -n "$REVIEW_COMMENTS" ]; then
      # Count only unresolved review threads 
      if [ -n "$(echo "$REVIEW_COMMENTS" | jq -r '.reviewThreads')" ]; then
        UNRESOLVED_THREADS=$(echo "$REVIEW_COMMENTS" | jq -r '[.reviewThreads[] | select(.isResolved == false)] | length // 0')
        # Only consider threads that are not marked as resolved
        COMMENT_COUNT=$UNRESOLVED_THREADS
        echo "    Found $UNRESOLVED_THREADS unresolved review threads"
      fi
    fi
    
    # Check review decision
    echo "    Checking review decision..."
    REVIEW_STATUS=$(gh pr view "$PR_NUM" --json reviewDecision 2>/dev/null)
    REVIEW_DECISION=$(echo "$REVIEW_STATUS" | jq -r '.reviewDecision // "NONE"')
    [ -z "$REVIEW_DECISION" ] && REVIEW_DECISION="UNKNOWN"
    
    # Get the full PR title and branch from GitHub
    echo "    Getting full PR title and branch..."
    PR_DATA=$(gh pr view "$PR_NUM" --json title,headRefName 2>/dev/null)
    if [ -n "$PR_DATA" ]; then
      # Extract the title from the JSON response
      FULL_PR_TITLE=$(echo "$PR_DATA" | jq -r '.title // empty')
      if [ -n "$FULL_PR_TITLE" ]; then
        echo "    Found PR title: $FULL_PR_TITLE"
        PR_TITLE_CLEAN="$FULL_PR_TITLE"
      fi
      
      # Extract the branch name
      PR_BRANCH=$(echo "$PR_DATA" | jq -r '.headRefName // empty')
      echo "    Found PR branch: $PR_BRANCH"
    fi
    
    # Check if this is a quick-fix PR
    IS_QUICK_FIX="false"
    if [[ "$PR_BRANCH" == *"quick-fix"* ]]; then
      IS_QUICK_FIX="true"
      echo "    This is a quick-fix PR"
    fi
    
    # Ensure numeric values are actually numeric
    if ! [[ "$FAILING_CHECKS" =~ ^[0-9]+$ ]]; then
      FAILING_CHECKS=0
    fi
    
    if ! [[ "$COMMENT_COUNT" =~ ^[0-9]+$ ]]; then
      COMMENT_COUNT=0
    fi
    
    # Log PR details 
    echo "    URL: $URL"
    echo "    Failing Checks: $FAILING_CHECKS"
    echo "    Comment Count: $COMMENT_COUNT"
    echo "    Is Draft: $IS_DRAFT"
    echo "    Mergeable: $MERGEABLE"
    echo "    Review Decision: $REVIEW_DECISION"
    
    # Format the PR entry without markdown syntax to avoid issues
    # Clean up the PR title for better display (remove brackets, etc.)
    PR_TITLE_CLEAN=$(echo "$PR_TITLE_CLEAN" | sed 's/\[//g' | sed 's/\]//g')
    PR_ENTRY="- $PR_TITLE_CLEAN ($URL)"
    
    # Build a reason string for the PR status
    REASONS=""
    
    if [ "$IS_DRAFT" == "true" ]; then
      REASONS="$REASONS Draft PR"
    fi
    
    if [ "$MERGEABLE" == "CONFLICTING" ]; then
      [ -n "$REASONS" ] && REASONS="$REASONS, "
      REASONS="${REASONS}Has conflicts"
    fi
    
    if [ "$FAILING_CHECKS" -gt 0 ]; then
      [ -n "$REASONS" ] && REASONS="$REASONS, "
      REASONS="${REASONS}Failing checks"
    fi
    
    if [ "$COMMENT_COUNT" -gt 0 ]; then
      [ -n "$REASONS" ] && REASONS="$REASONS, "
      REASONS="${REASONS}Has unresolved comments"
    fi
    
    if [ "$REVIEW_DECISION" == "CHANGES_REQUESTED" ]; then
      [ -n "$REASONS" ] && REASONS="$REASONS, "
      REASONS="${REASONS}Changes requested"
    fi
    
    # Add the PR status reason to the PR entry with better formatting
    if [ -n "$REASONS" ]; then
      # Use proper indentation with consistent tab formatting
      FULL_PR_ENTRY="$PR_ENTRY\n\t- $REASONS"
    else
      FULL_PR_ENTRY="$PR_ENTRY"
    fi
    
    # Determine PR category based on problems and quick-fix status
    if [ "$FAILING_CHECKS" -eq 0 ] && 
       [ "$COMMENT_COUNT" -eq 0 ] && 
       [ "$MERGEABLE" != "CONFLICTING" ] && 
       [ "$IS_DRAFT" != "true" ] && 
       [ "$REVIEW_DECISION" != "CHANGES_REQUESTED" ]; then
      # Ready for merge - All checks passing, no comments, no conflicts, not a draft, no changes requested
      if [ "$IS_QUICK_FIX" == "true" ]; then
        echo -e "$FULL_PR_ENTRY" >> "$QUICK_FIX_READY_FILE"
        echo "    Category: Quick-Fix Ready for Merge (no issues)"
      else
        echo -e "$FULL_PR_ENTRY" >> "$READY_FILE"
        echo "    Category: Ready for Merge (no issues)"
      fi
    else
      # Needs attention - Has at least one problem
      if [ "$IS_QUICK_FIX" == "true" ]; then
        echo -e "$FULL_PR_ENTRY" >> "$QUICK_FIX_ATTENTION_FILE"
        echo "    Category: Quick-Fix Needs Attention ($REASONS)"
      else
        echo -e "$FULL_PR_ENTRY" >> "$NEEDS_ATTENTION_FILE"
        echo "    Category: Needs Attention ($REASONS)"
      fi
    fi
  done
done

# Create the PR review content with fixed markdown syntax
PR_REVIEW_FILE="$TEMP_DIR/pr_review.md"

# First run through all repos to count total PRs
TOTAL_PRS=0
for i in "${!REPO_PATHS[@]}"; do
  REPO_PATH="${REPO_PATHS[$i]}"
  if [ -d "$REPO_PATH/.git" ]; then
    PR_COUNT=$(cd "$REPO_PATH" && gh pr list --author "@me" | wc -l)
    TOTAL_PRS=$((TOTAL_PRS + PR_COUNT))
  fi
done

# Generate PR summary
cat > "$PR_REVIEW_FILE" << EOF
### PR Reviews

> Last updated: $(date '+%Y-%m-%d %H:%M:%S')  |  Total PRs: $TOTAL_PRS

**Quick-Fix PRs Ready for Merge:**
*Fast-track PRs with "quick-fix" in branch name - All checks passing, ready to merge*
EOF

# Add quick-fix ready PRs
if [ ! -s "$QUICK_FIX_READY_FILE" ]; then
  echo "- No quick-fix PRs ready for merge" >> "$PR_REVIEW_FILE"
else
  # Output each entry directly
  cat "$QUICK_FIX_READY_FILE" >> "$PR_REVIEW_FILE"
  # Count PRs ready for merge - count lines that start with hyphen
  QUICK_FIX_READY_COUNT=$(grep -c "^-" "$QUICK_FIX_READY_FILE")
  echo "" >> "$PR_REVIEW_FILE" 
  echo "> Total: $QUICK_FIX_READY_COUNT quick-fix PR(s) ready for merge" >> "$PR_REVIEW_FILE"
fi
echo "" >> "$PR_REVIEW_FILE"

# Add quick-fix PRs needing attention
echo "**Quick-Fix PRs Needing Attention:**" >> "$PR_REVIEW_FILE"
echo "*Quick-fix PRs with failing checks, unresolved comments, conflicts, or other issues*" >> "$PR_REVIEW_FILE"
if [ ! -s "$QUICK_FIX_ATTENTION_FILE" ]; then
  echo "- No quick-fix PRs needing attention" >> "$PR_REVIEW_FILE"
else
  # Output each entry directly
  cat "$QUICK_FIX_ATTENTION_FILE" >> "$PR_REVIEW_FILE"
  # Count PRs needing attention - each PR takes up 2 lines with the reasons on the second line
  QUICK_FIX_ATTENTION_COUNT=$(grep -c "^-" "$QUICK_FIX_ATTENTION_FILE")
  echo "" >> "$PR_REVIEW_FILE"
  echo "> Total: $QUICK_FIX_ATTENTION_COUNT quick-fix PR(s) needing attention" >> "$PR_REVIEW_FILE"
fi
echo "" >> "$PR_REVIEW_FILE"

# Add regular PRs ready for merge
echo "**Regular PRs Ready for Merge:**" >> "$PR_REVIEW_FILE"
echo "*All checks passing, no unresolved comments, no changes requested, no conflicts, not a draft*" >> "$PR_REVIEW_FILE"
if [ ! -s "$READY_FILE" ]; then
  echo "- No regular PRs ready for merge" >> "$PR_REVIEW_FILE"
else
  # Output each entry directly
  cat "$READY_FILE" >> "$PR_REVIEW_FILE"
  # Count PRs ready for merge - count lines that start with hyphen
  READY_COUNT=$(grep -c "^-" "$READY_FILE")
  echo "" >> "$PR_REVIEW_FILE" 
  echo "> Total: $READY_COUNT regular PR(s) ready for merge" >> "$PR_REVIEW_FILE"
fi
echo "" >> "$PR_REVIEW_FILE"

# Add regular PRs needing attention
echo "**Regular PRs Needing Attention:**" >> "$PR_REVIEW_FILE"
echo "*Regular PRs with failing checks, unresolved comments, conflicts, or other issues*" >> "$PR_REVIEW_FILE"
if [ ! -s "$NEEDS_ATTENTION_FILE" ]; then
  echo "- No regular PRs needing attention" >> "$PR_REVIEW_FILE"
else
  # Output each entry directly
  cat "$NEEDS_ATTENTION_FILE" >> "$PR_REVIEW_FILE"
  # Count PRs needing attention - each PR takes up 2 lines with the reasons on the second line
  ATTENTION_COUNT=$(grep -c "^-" "$NEEDS_ATTENTION_FILE")
  echo "" >> "$PR_REVIEW_FILE"
  echo "> Total: $ATTENTION_COUNT regular PR(s) needing attention" >> "$PR_REVIEW_FILE"
fi
echo "" >> "$PR_REVIEW_FILE"

# Add other PRs
echo "**Other PRs:**" >> "$PR_REVIEW_FILE"
if [ ! -s "$OTHER_FILE" ]; then
  echo "- No other PRs" >> "$PR_REVIEW_FILE"
else
  # Output each entry directly
  cat "$OTHER_FILE" >> "$PR_REVIEW_FILE"
  # Count other PRs - count lines that start with hyphen
  OTHER_COUNT=$(grep -c "^-" "$OTHER_FILE")
  echo "" >> "$PR_REVIEW_FILE"
  echo "> Total: $OTHER_COUNT other PR(s)" >> "$PR_REVIEW_FILE"
fi
echo "" >> "$PR_REVIEW_FILE"

# Output or update the daily note
if [ -n "$DAILY_NOTE" ] && [ -f "$DAILY_NOTE" ]; then
  # Check if daily note has the required separator
  if ! grep -q "^--- 📋 PR Review End ---$" "$DAILY_NOTE"; then
    echo "ERROR: Daily note $DAILY_NOTE is missing required separator '--- 📋 PR Review End ---'"
    echo "Please add this separator to mark where the PR script should stop updating content."
    echo "The separator should be placed before any sections you want to preserve (like session tracking)."
    echo ""
    echo "Just outputting PR summary to stdout instead:"
    echo "================ PR REVIEW SUMMARY ================"
    cat "$PR_REVIEW_FILE"
    echo "=================================================="
    exit 1
  fi
  
  # Create a temporary file for the updated content
  TEMP_FILE=$(mktemp)
  
  # Create a completely new file from scratch
  {
    # Extract YAML front matter and main title
    sed -n '1,/# Daily Notes/p' "$DAILY_NOTE"
    
    # Extract the Work Summary section
    echo -e "\n## Work Summary\n"
    echo "Today I worked on:"
    
    # Extract Project/Ticket sections
    grep -A 5 "### Project/Ticket:" "$DAILY_NOTE"
    
    # Add PR Reviews section
    cat "$PR_REVIEW_FILE"
    
    # Add remaining sections from template if it exists
    if [ -f "$TEMPLATE_FILE" ]; then
      # Check if template has the required separator
      if ! grep -q "^--- 📋 PR Review End ---$" "$TEMPLATE_FILE"; then
        echo "Warning: Template file $TEMPLATE_FILE is missing required separator '--- 📋 PR Review End ---'"
        echo "Please add this separator to mark where the PR script should stop extracting content."
        # Continue without adding template sections
      else
        # Extract everything after PR Reviews from the template, preserving structure
        sed -n '/^--- 📋 PR Review End ---$/,/^--- 📋 PR Review End ---$/p' "$TEMPLATE_FILE" | \
          head -n -1 | \
          sed "s/{{date:YYYY-MM-DD}}/$TODAY/g" | \
          sed "s/{{date:MMMM D, YYYY}}/$MONTH_FULL $DAY, $YEAR/g" | \
          sed "s/{{time:HH:mm:ss}}/$(date '+%H:%M:%S')/g"
      fi
    fi
  } > "$TEMP_FILE"
  
  # Replace the original file with our new version
  mv "$TEMP_FILE" "$DAILY_NOTE"
  
  echo "PR review added to $DAILY_NOTE"
  echo "Open with your editor to review"
else
  # Just display the PR summary to stdout
  echo "================ PR REVIEW SUMMARY ================"
  cat "$PR_REVIEW_FILE"
  echo "=================================================="
fi