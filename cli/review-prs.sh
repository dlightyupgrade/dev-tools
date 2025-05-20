#!/bin/bash
# Morning PR Review Script for CoreSrv repositories
# Creates a markdown report of open PRs categorized by status
#
# Uses GitHub CLI to fetch detailed PR information including:
# - Pull request review status
# - Status check results
# - PR comments and review threads
# - Mergeable status
#
# Updated: $(date +"%Y-%m-%d")
#
# NOTE: This script requires gh (GitHub CLI) to be installed and authenticated
# You can install it with:
#   brew install gh
# And authenticate with:
#   gh auth login

TODAY=$(date +"%Y-%m-%d")
YEAR=$(date +"%Y")
MONTH=$(date +"%m")
MONTH_NAME=$(date +"%b")
DAILY_NOTE_DIR="/Users/dlighty/notes/daily/$YEAR/$MONTH-$MONTH_NAME"
DAILY_NOTE="$DAILY_NOTE_DIR/$TODAY.md"

# Create daily notes directory structure if needed
mkdir -p "$DAILY_NOTE_DIR"

# Create daily note if it doesn't exist
if [ ! -f "$DAILY_NOTE" ]; then
  MONTH_FULL=$(date +"%B")
  DAY=$(date +"%d")
  
  # Remove leading zero from day
  DAY=$(echo $DAY | sed 's/^0//')
  
  cat > "$DAILY_NOTE" << EOF
---
title: Daily Notes - $MONTH_FULL $DAY, $YEAR
date: $TODAY
tags: [daily, work-log]
---

# Daily Notes - $MONTH_FULL $DAY, $YEAR

## Work Summary

Today I worked on:

### Project/Ticket: [Project Name]

- 
- 
- 

EOF
fi

# CoreSrv repositories with their local paths
REPO_PATHS=(
  "/Users/dlighty/code/loan-hardship-servicing-srvc"
  "/Users/dlighty/code/creditline-hardship-servicing-srvc"
  "/Users/dlighty/code/loan-servicing-srvc"
  "/Users/dlighty/code/actor-hardship-srvc"
)

# Repository names for display
REPO_NAMES=(
  "loan-hardship-servicing-srvc"
  "creditline-hardship-servicing-srvc"
  "loan-servicing-srvc" 
  "actor-hardship-srvc"
)

# Create temporary files for PR lists
READY_FILE=$(mktemp)
NEEDS_ATTENTION_FILE=$(mktemp)
OTHER_FILE=$(mktemp)

# Create temporary directory for working files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

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
    OWNER=$(echo $REPO_URL | sed -E 's/.*github.com[:\/]([^\/]+)\/([^\/]+)(\.git)?$/\1/')
    REPO=$(echo $REPO_URL | sed -E 's/.*github.com[:\/]([^\/]+)\/([^\/]+)(\.git)?$/\2/')
    CLEAN_REPO=${REPO%.git}
    
    # Standard URL pattern
    URL="https://github.com/$OWNER/$CLEAN_REPO/pull/$PR_NUM"
    
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
    # These are more reliable than the JSON extraction
    
    # Check if it's a draft PR
    echo "    Checking if draft PR..."
    DRAFT_CHECK=$(cd "$REPO_PATH" && gh pr view "$PR_NUM" --json isDraft 2>/dev/null)
    IS_DRAFT=$(echo "$DRAFT_CHECK" | jq -r '.isDraft // false')
    [ -z "$IS_DRAFT" ] && IS_DRAFT="false"
    
    # Check if it has failing checks using status API - more reliable
    echo "    Checking CI status..."
    CHECK_STATUS=$(cd "$REPO_PATH" && gh pr view "$PR_NUM" --json statusCheckRollup 2>/dev/null)
    
    # Default to passing if we can't determine (avoid false positives)
    FAILING_CHECKS=0
    
    if [ -n "$CHECK_STATUS" ]; then
        # Check if any status has conclusion != "SUCCESS" and != null and != "NEUTRAL"
        FAILURE_COUNT=$(echo "$CHECK_STATUS" | jq '.statusCheckRollup | length as $total | if $total > 0 then [.statusCheckRollup[] | select(.conclusion != "SUCCESS" and .conclusion != null and .conclusion != "NEUTRAL")] | length else 0 end' 2>/dev/null)
        
        # If jq call failed or gave empty result, try a simpler approach
        if [ -z "$FAILURE_COUNT" ] || [ "$FAILURE_COUNT" = "null" ]; then
            echo "    Failed to parse status check data, falling back to command line output"
            # Try the command line directly with specific output checking
            CI_OUTPUT=$(cd "$REPO_PATH" && gh pr checks "$PR_NUM" 2>/dev/null)
            # We need to be very careful here because "fail" appears in URLs and other places
            # Only look for the exact word "fail" at the beginning of a column
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
    MERGE_STATUS=$(cd "$REPO_PATH" && gh pr view "$PR_NUM" --json mergeable 2>/dev/null)
    MERGEABLE=$(echo "$MERGE_STATUS" | jq -r '.mergeable // "UNKNOWN"')
    [ -z "$MERGEABLE" ] && MERGEABLE="UNKNOWN"
    
    # Check for unresolved comments
    echo "    Checking for unresolved comments..."
    REVIEW_COMMENTS=$(cd "$REPO_PATH" && gh pr view "$PR_NUM" --json comments,reviewThreads 2>/dev/null)
    if [ -n "$REVIEW_COMMENTS" ]; then
        # Count only unresolved review threads 
        if [ -n "$(echo "$REVIEW_COMMENTS" | jq -r '.reviewThreads')" ]; then
            UNRESOLVED_THREADS=$(echo "$REVIEW_COMMENTS" | jq -r '[.reviewThreads[] | select(.isResolved == false)] | length // 0')
            # Only consider threads that are not marked as resolved
            COMMENT_COUNT=$UNRESOLVED_THREADS
            echo "    Found $UNRESOLVED_THREADS unresolved review threads"
        else
            # No review threads found
            COMMENT_COUNT=0
        fi
    else
        COMMENT_COUNT=0
    fi
    
    # Check review decision
    echo "    Checking review decision..."
    REVIEW_STATUS=$(cd "$REPO_PATH" && gh pr view "$PR_NUM" --json reviewDecision 2>/dev/null)
    REVIEW_DECISION=$(echo "$REVIEW_STATUS" | jq -r '.reviewDecision // "NONE"')
    [ -z "$REVIEW_DECISION" ] && REVIEW_DECISION="UNKNOWN"
    
    # Get the full PR title from GitHub
    echo "    Getting full PR title..."
    PR_TITLE_DATA=$(cd "$REPO_PATH" && gh pr view "$PR_NUM" --json title 2>/dev/null)
    if [ -n "$PR_TITLE_DATA" ]; then
        # Extract the title from the JSON response
        FULL_PR_TITLE=$(echo "$PR_TITLE_DATA" | jq -r '.title // empty')
        if [ -n "$FULL_PR_TITLE" ]; then
            echo "    Found PR title: $FULL_PR_TITLE"
            PR_TITLE_CLEAN="$FULL_PR_TITLE"
        fi
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
    
    # Fix the URL by removing .git if present
    URL=${URL/.git\//\/}
    
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
      if [ -n "$REASONS" ]; then
        REASONS="$REASONS, "
      fi
      REASONS="${REASONS}Has conflicts"
    fi
    
    if [ "$FAILING_CHECKS" -gt 0 ]; then
      if [ -n "$REASONS" ]; then
        REASONS="$REASONS, "
      fi
      REASONS="${REASONS}Failing checks"
    fi
    
    if [ "$COMMENT_COUNT" -gt 0 ]; then
      if [ -n "$REASONS" ]; then
        REASONS="$REASONS, "
      fi
      REASONS="${REASONS}Has unresolved comments"
    fi
    
    if [ "$REVIEW_DECISION" == "CHANGES_REQUESTED" ]; then
      if [ -n "$REASONS" ]; then
        REASONS="$REASONS, "
      fi
      REASONS="${REASONS}Changes requested"
    fi
    
    # Add the PR status reason to the PR entry with better formatting
    if [ -n "$REASONS" ]; then
      # Use proper indentation with consistent tab formatting
      FULL_PR_ENTRY="$PR_ENTRY\n\t- $REASONS"
    else
      FULL_PR_ENTRY="$PR_ENTRY"
    fi
    
    # Determine PR category based on problems
    if [ "$FAILING_CHECKS" -eq 0 ] && [ "$COMMENT_COUNT" -eq 0 ] && [ "$MERGEABLE" != "CONFLICTING" ] && [ "$IS_DRAFT" != "true" ] && [ "$REVIEW_DECISION" != "CHANGES_REQUESTED" ]; then
      # Ready for merge - All checks passing, no comments, no conflicts, not a draft, no changes requested
      echo -e "$FULL_PR_ENTRY" >> "$READY_FILE"
      echo "    Category: Ready for Merge (no issues)"
    else
      # Needs attention - Has at least one problem
      echo -e "$FULL_PR_ENTRY" >> "$NEEDS_ATTENTION_FILE"
      echo "    Category: Needs Attention ($REASONS)"
    fi
  done
  
  # We're skipping PRs that need my review since the user has another alert for those
done

# Create a temporary file for the updated content
TEMP_FILE=$(mktemp)

# Create the PR review content with fixed markdown syntax
PR_REVIEW_FILE="$TEMP_DIR/pr_review.md"

# First run through all repos to count total PRs
TOTAL_PRS=0
for i in "${!REPO_PATHS[@]}"; do
  REPO_PATH="${REPO_PATHS[$i]}"
  PR_COUNT=$(cd "$REPO_PATH" && gh pr list --author "@me" | wc -l)
  TOTAL_PRS=$((TOTAL_PRS + PR_COUNT))
done

cat > "$PR_REVIEW_FILE" << EOF
### PR Reviews

> Last updated: $(date '+%Y-%m-%d %H:%M:%S')  |  Total PRs: $TOTAL_PRS

**PRs Ready for Merge:**
*All checks passing, no unresolved comments, no changes requested, no conflicts, not a draft*
EOF

if [ ! -s "$READY_FILE" ]; then
  echo "- No PRs ready for merge" >> "$PR_REVIEW_FILE"
else
  # Output each entry directly
  cat "$READY_FILE" >> "$PR_REVIEW_FILE"
  # Count PRs ready for merge - count lines that start with hyphen
  READY_COUNT=$(grep -c "^-" "$READY_FILE")
  echo "" >> "$PR_REVIEW_FILE" 
  echo "> Total: $READY_COUNT PR(s) ready for merge" >> "$PR_REVIEW_FILE"
fi
echo "" >> "$PR_REVIEW_FILE"

echo "**PRs Needing Attention:**" >> "$PR_REVIEW_FILE"
echo "*PRs with failing checks, unresolved comments, conflicts, or other issues*" >> "$PR_REVIEW_FILE"
if [ ! -s "$NEEDS_ATTENTION_FILE" ]; then
  echo "- No PRs needing attention" >> "$PR_REVIEW_FILE"
else
  # Output each entry directly
  cat "$NEEDS_ATTENTION_FILE" >> "$PR_REVIEW_FILE"
  # Count PRs needing attention - each PR takes up 2 lines with the reasons on the second line
  ATTENTION_COUNT=$(grep -c "^-" "$NEEDS_ATTENTION_FILE")
  echo "" >> "$PR_REVIEW_FILE"
  echo "> Total: $ATTENTION_COUNT PR(s) needing attention" >> "$PR_REVIEW_FILE"
fi
echo "" >> "$PR_REVIEW_FILE"

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
  
  # Add Other Tasks section
  echo "### Other Tasks"
  echo ""
  echo "- "
  echo "- "
  echo ""
  
  # Add Notes & Observations section
  echo "## Notes & Observations"
  echo ""
  echo "- "
  echo "- "
  echo ""
} > "$TEMP_FILE"

# Replace the original file with our new version
mv "$TEMP_FILE" "$DAILY_NOTE"

# Clean up temporary files
rm -f "$READY_FILE" "$NEEDS_ATTENTION_FILE" "$OTHER_FILE"
# The TEMP_DIR will be cleaned up by the EXIT trap we set earlier

echo "PR review added to $DAILY_NOTE"
echo "Open with your editor to review"