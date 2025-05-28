#!/bin/bash

# ===============================================================
# create-branch.sh
# Creates a new git branch from master and adds it to tracking config
# Usage: create-branch.sh [ticket-id] [branch-description]
# ===============================================================

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
PROJECTS_DIR="$HOME/code"
CONFIG_DIR="$HOME/.config/dev-tools"
REBASE_FILE_NAME="to-rebase.txt"
REBASE_FILE="$CONFIG_DIR/$REBASE_FILE_NAME"
BASE_BRANCH="master"

# Show help if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  echo -e "${BLUE}${BOLD}Branch Creator${NC}"
  echo -e "Creates a new git branch from master and adds it to tracking config"
  echo ""
  echo -e "${YELLOW}Usage:${NC}"
  echo -e "  $0 [ticket-id] [branch-description]"
  echo ""
  echo -e "${YELLOW}Arguments:${NC}"
  echo -e "  ticket-id           Ticket identifier (e.g., SI-1234 or no-jira)"
  echo -e "  branch-description  Brief description for the branch (will be kebab-cased)"
  echo ""
  echo -e "${YELLOW}Features:${NC}"
  echo -e "  - Updates master branch before branching"
  echo -e "  - Creates properly formatted branch name (SI-1234_fix-readme or no-jira-fix-typo)"
  echo -e "  - Adds branch to tracking file ($REBASE_FILE_NAME) for future updates/rebases"
  echo ""
  echo -e "${YELLOW}Examples:${NC}"
  echo -e "  $0 SI-1234 fix-readme"
  echo -e "  $0 no-jira update-documentation"
  echo -e "  $0 SI-8765 \"add login validation\""
  exit 0
fi

# Process command line arguments
if [ "$#" -lt 2 ]; then
  echo -e "${RED}Error: Insufficient arguments.${NC}"
  echo -e "Usage: $0 [ticket-id] [branch-description]"
  echo -e "Example: $0 SI-1234 fix-readme"
  echo -e "Example: $0 no-jira fix-typo"
  echo -e "For more details: $0 --help"
  exit 1
fi

TICKET="$1"
DESCRIPTION="$2"

# Convert ticket ID and description to lowercase with hyphens for consistency
TICKET_LOWER=$(echo "$TICKET" | tr '[:upper:]' '[:lower:]')
DESCRIPTION_KEBAB=$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Normalize "no jira" variations to "no-jira"
if [[ "$TICKET_LOWER" == "nojira" || "$TICKET_LOWER" == "no_jira" || "$TICKET_LOWER" == "no-jira" || "$TICKET_LOWER" == "no jira" ]]; then
  TICKET_LOWER="no-jira"
  BRANCH_NAME="${TICKET_LOWER}-${DESCRIPTION_KEBAB}"
else
  # Keep the original case for the ticket for better readability in the tracking file
  BRANCH_NAME="${TICKET}_${DESCRIPTION_KEBAB}"
fi

# Determine current directory's repo name
CURRENT_REPO=$(basename "$PWD")
echo -e "${BLUE}Current repository: ${BOLD}$CURRENT_REPO${NC}"

# Check if we're in a git repository
if [ ! -d ".git" ]; then
  echo -e "${RED}Error: Not a git repository!${NC}"
  exit 1
fi

# Update master branch
echo -e "${YELLOW}Updating $BASE_BRANCH branch...${NC}"
git fetch origin
git checkout "$BASE_BRANCH"

# Check if there was an error checking out master
if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Could not checkout $BASE_BRANCH branch.${NC}"
  echo -e "${RED}Please commit or stash your changes before creating a new branch.${NC}"
  exit 1
fi

git pull origin "$BASE_BRANCH"

# Check if pull was successful
if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Failed to pull latest changes from $BASE_BRANCH.${NC}"
  exit 1
fi

# Create and checkout new branch
echo -e "${YELLOW}Creating new branch: ${BOLD}$BRANCH_NAME${NC}"
git checkout -b "$BRANCH_NAME"

# Check if branch creation was successful
if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Failed to create branch $BRANCH_NAME.${NC}"
  exit 1
fi

# Add branch to tracking file if it doesn't exist already
if [ -f "$REBASE_FILE" ]; then
  # Check if branch is already in tracking file
  if ! grep -q "$CURRENT_REPO:$BRANCH_NAME" "$REBASE_FILE"; then
    echo -e "${YELLOW}Adding branch to tracking file: $REBASE_FILE${NC}"
    echo "$CURRENT_REPO:$BRANCH_NAME" >> "$REBASE_FILE"
    echo -e "${GREEN}Branch added to tracking file.${NC}"
  else
    echo -e "${YELLOW}Branch already exists in tracking file.${NC}"
  fi
else
  echo -e "${RED}Warning: Tracking file $REBASE_FILE does not exist.${NC}"
  echo -e "${YELLOW}Creating tracking file...${NC}"
  mkdir -p "$(dirname "$REBASE_FILE")"
  echo "# Branches to rebase onto $BASE_BRANCH" > "$REBASE_FILE"
  echo "# Format: one branch name per line, or 'repo:branch' to target specific repositories" >> "$REBASE_FILE"
  echo "$CURRENT_REPO:$BRANCH_NAME" >> "$REBASE_FILE"
  echo -e "${GREEN}Tracking file created and branch added.${NC}"
fi

echo -e "\n${GREEN}=== Summary ===${NC}"
echo -e "${GREEN}✓${NC} Created branch: ${BOLD}$BRANCH_NAME${NC}"
echo -e "${GREEN}✓${NC} Based on: $BASE_BRANCH"
echo -e "${GREEN}✓${NC} Added to tracking file for rebase updates"
echo -e "${GREEN}✓${NC} Ready to make changes"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Make your changes"
echo -e "  2. Commit with: ${BOLD}git add . && git commit -m \"$TICKET: Your commit message\"${NC}"
echo -e "  3. Push with: ${BOLD}git push -u origin $BRANCH_NAME${NC}"