#!/bin/bash
# Enable associative arrays (requires bash 4+)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "This script requires Bash version 4 or higher for associative arrays."
  echo "Your Bash version is ${BASH_VERSION}"
  echo "Using simple array fallback mode."
fi

#===============================================================
# CONFIGURATION
#===============================================================
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

# Repositories will be loaded from config file

#===============================================================
# SCRIPT LOGIC
#===============================================================

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to create example config files if needed
create_example_files() {
  local config_path="$1"
  local rebase_path="$2"
  
  # Create example config file if it doesn't exist
  if [ ! -f "$config_path" ]; then
    echo -e "${YELLOW}Creating example config file at $config_path${NC}"
    mkdir -p "$(dirname "$config_path")"
    cat > "$config_path" << EOF
# Configuration file for update-core-repos.sh
# List repositories to update, one per line
# You can use relative paths (from $PROJECTS_DIR) or absolute paths
# Lines starting with # are treated as comments

# Core Service repositories
loan-hardship-servicing-srvc
creditline-hardship-servicing-srvc
loan-servicing-srvc
actor-hardship-srvc

# Example of absolute path (commented out)
# /Users/dlighty/code/personal-dev-tools
EOF
  fi
  
  # Create example rebase file if it doesn't exist
  if [ ! -f "$rebase_path" ]; then
    echo -e "${YELLOW}Creating example rebase file at $rebase_path${NC}"
    mkdir -p "$(dirname "$rebase_path")"
    cat > "$rebase_path" << EOF
# Branches to rebase onto $BASE_BRANCH
# Format: one branch name per line, or 'repo:branch' to target specific repositories
# Examples:
# feature-branch              # Rebase 'feature-branch' in all repositories where it exists
# loan-hardship-servicing-srvc:SI-1234-feature  # Rebase only in specific repository
EOF
  fi
}

# Parse command line options
usage() {
  echo "Usage: $0 [OPTIONS] [CONFIG_FILE]"
  echo "Options:"
  echo "  -a, --ask       Ask before switching back to original branch"
  echo "  -r, --rebase    Specify a custom rebase file"
  echo "  -g, --generate  Generate example config files and exit"
  echo "  -n, --no-push   Don't force push rebased branches to origin"
  echo "  -h, --help      Display this help message"
  echo ""
  echo "If CONFIG_FILE is not specified, defaults to $PROJECTS_DIR/$CONFIG_FILE_NAME"
  echo "The config file should contain repository paths to update, one per line."
  echo "Lines starting with '#' are treated as comments."
  echo "The rebase file contains branch names to rebase, one per line."
  echo "Each line can be either a simple branch name or in 'repo:branch' format."
  echo ""
  echo "By default, successfully rebased branches will be force-pushed to origin."
  echo "Use -n/--no-push to disable this behavior."
  exit 1
}

# Parse command line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -a|--ask)
      ASK_BEFORE_SWITCH="true"
      shift 1
      ;;
    -r|--rebase)
      REBASE_FILE_ARG="$2"
      shift 2
      ;;
    -n|--no-push)
      FORCE_PUSH="false"
      shift 1
      ;;
    -g|--generate)
      # Generate example config files and exit
      CONFIG_FILE_PATH="$PROJECTS_DIR/$CONFIG_FILE_NAME"
      REBASE_FILE_PATH="$PROJECTS_DIR/$REBASE_FILE_NAME"
      create_example_files "$CONFIG_FILE_PATH" "$REBASE_FILE_PATH"
      echo -e "${GREEN}Example config files created. Edit them as needed and run the script again.${NC}"
      exit 0
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      # First non-option argument is the config file
      if [ -z "$CONFIG_FILE_ARG" ]; then
        CONFIG_FILE_ARG="$1"
      else
        echo "Unexpected argument: $1"
        usage
      fi
      shift
      ;;
  esac
done

# File containing repositories to update
CONFIG_FILE="${CONFIG_FILE_ARG:-$PROJECTS_DIR/$CONFIG_FILE_NAME}"
REBASE_FILE="${REBASE_FILE_ARG:-$PROJECTS_DIR/$REBASE_FILE_NAME}"

# Create example files if they don't exist
create_example_files "$CONFIG_FILE" "$REBASE_FILE"

# Load repositories from config file
REPOS=()
if [ -f "$CONFIG_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Strip leading/trailing whitespace
    line=$(echo "$line" | xargs)
    
    # If line starts with '/', it's an absolute path
    # Otherwise, prepend the projects directory
    if [[ "$line" == /* ]]; then
      REPOS+=("$line")
    else
      REPOS+=("$PROJECTS_DIR/$line")
    fi
  done < "$CONFIG_FILE"
else
  echo -e "${RED}Error: Config file $CONFIG_FILE does not exist!${NC}"
  echo "Please create a config file with repository paths, one per line."
  echo "Example:"
  echo "loan-hardship-servicing-srvc"
  echo "creditline-hardship-servicing-srvc"
  exit 1
fi

# Function to update a repository
update_repo() {
  local repo_path=$1
  local repo_name=$(basename "$repo_path")
  
  echo -e "\n${YELLOW}Processing $repo_name...${NC}"
  
  # Initialize arrays to track branch results
  local success_branches=()
  local failed_branches=()
  local skipped_branches=()
  
  # Find the repo index in the global arrays
  repo_index=-1
  for i in "${!REPO_NAMES[@]}"; do
    if [[ "${REPO_NAMES[$i]}" == "$repo_name" ]]; then
      repo_index=$i
      break
    fi
  done
  
  # Check if directory exists
  if [ ! -d "$repo_path" ]; then
    echo -e "${RED}Repository directory $repo_path does not exist!${NC}"
    if [ $repo_index -ge 0 ]; then
      REPO_RESULTS[$repo_index]="${RED}Directory not found${NC}"
    fi
    return 1
  fi
  
  # Navigate to repository
  cd "$repo_path" || return 1
  
  # Check if it's a git repository
  if [ ! -d ".git" ]; then
    echo -e "${RED}$repo_path is not a git repository!${NC}"
    if [ $repo_index -ge 0 ]; then
      REPO_RESULTS[$repo_index]="${RED}Not a git repository${NC}"
    fi
    return 1
  fi
  
  # Fetch and pull master
  echo "Fetching latest changes..."
  git fetch origin
  
  # Save current branch to switch back to later
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  
  # Check if there are any pending changes
  has_changes=false
  if [[ -n "$(git status --porcelain)" ]]; then
    has_changes=true
    echo -e "${YELLOW}[$repo_name] Detected uncommitted changes in $current_branch.${NC}"
  fi
  
  # Stash changes if needed and switch to base branch
  stash_created=false
  if [ "$current_branch" != "$BASE_BRANCH" ]; then
    if [ "$has_changes" = true ]; then
      echo -e "${YELLOW}[$repo_name] Auto-stashing changes before switching branches...${NC}"
      stash_message="auto-stash-before-update-$(date +%Y%m%d-%H%M%S)"
      git stash push -m "$stash_message"
      stash_created=true
    fi
    
    echo "Switching to $BASE_BRANCH branch..."
    git checkout "$BASE_BRANCH"
  elif [ "$has_changes" = true ]; then
    echo -e "${YELLOW}[$repo_name] Auto-stashing changes before pulling...${NC}"
    stash_message="auto-stash-before-update-$(date +%Y%m%d-%H%M%S)"
    git stash push -m "$stash_message"
    stash_created=true
  fi
  
  echo "Pulling latest changes for $BASE_BRANCH..."
  pull_result=$(git pull origin "$BASE_BRANCH" 2>&1)
  
  # Get branches to rebase from the rebase file
  branches_to_rebase=()
  
  if [ -f "$REBASE_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      # Skip empty lines
      [ -z "$line" ] && continue
      
      # Check if line matches either repo:branch format or just branch format
      if [[ "$line" == "$repo_name:"* ]]; then
        # Extract branch name after repo prefix
        branch=${line#*:}
        # NEVER rebase master/main branches
        if [ "$branch" = "master" ] || [ "$branch" = "main" ]; then
          echo -e "${YELLOW}[$repo_name] Ignoring $branch in rebase list - protected branch.${NC}"
          continue
        fi
        branches_to_rebase+=("$branch")
      elif ! [[ "$line" == *":"* ]]; then
        # Line doesn't contain colon, treat as branch name
        # NEVER rebase master/main branches
        if [ "$line" = "master" ] || [ "$line" = "main" ]; then
          echo -e "${YELLOW}[$repo_name] Ignoring $line in rebase list - protected branch.${NC}"
          continue
        fi
        branches_to_rebase+=("$line")
      fi
    done < "$REBASE_FILE"
  fi
  
  # Process each branch that needs rebasing
  has_conflict=false
  for branch in "${branches_to_rebase[@]}"; do
    # Extra safety check to never rebase master/main branches
    if [ "$branch" = "$BASE_BRANCH" ] || [ "$branch" = "master" ] || [ "$branch" = "main" ]; then
      echo -e "${YELLOW}[$repo_name] Skipping $branch as it's a protected branch.${NC}"
      skipped_branches+=("$branch (protected branch)")
      continue
    fi
    
    echo "Rebasing branch '$branch' on $BASE_BRANCH in $repo_name..."
    
    # Check if branch exists locally
    if ! git show-ref --verify --quiet refs/heads/"$branch"; then
      echo -e "${YELLOW}[$repo_name] Branch '$branch' doesn't exist locally, skipping.${NC}"
      skipped_branches+=("$branch (not found locally)")
      continue
    fi
    
    # Switch to the branch
    git checkout "$branch"
    
    # Rebase on master
    rebase_result=$(git rebase "$BASE_BRANCH" 2>&1)
    if echo "$rebase_result" | grep -q "CONFLICT"; then
      echo -e "${RED}[$repo_name] Merge conflicts during rebase of '$branch'! Manual intervention required.${NC}"
      git rebase --abort
      has_conflict=true
      failed_branches+=("$branch")
    else
      echo -e "${GREEN}[$repo_name] Successfully rebased '$branch' on $BASE_BRANCH.${NC}"
      
      # Force push if enabled
      if [ "$FORCE_PUSH" = "true" ]; then
        echo -e "${YELLOW}[$repo_name] Force pushing $branch to origin...${NC}"
        push_result=$(git push origin "$branch" --force 2>&1)
        
        if [ $? -eq 0 ]; then
          echo -e "${GREEN}[$repo_name] Successfully pushed $branch to origin.${NC}"
          success_branches+=("$branch (rebased & pushed)")
        else
          echo -e "${RED}[$repo_name] Failed to push $branch to origin: ${NC}"
          echo "$push_result"
          # Still count as success for rebase, but note push failure
          success_branches+=("$branch (rebased but push failed)")
        fi
      else
        success_branches+=("$branch")
      fi
    fi
  done
  
  # Switch back to the original branch
  switch_back=true
  if [ "$has_conflict" = false ] && [ "$current_branch" != "$BASE_BRANCH" ]; then
    if [ "$ASK_BEFORE_SWITCH" = "true" ]; then
      read -p "Switch back to '$current_branch' branch? (y/n): " answer
      case ${answer:0:1} in
        n|N )
          switch_back=false
          if [ "$stash_created" = true ]; then
            echo -e "${YELLOW}[$repo_name] Warning: Changes were stashed but you chose to stay on $BASE_BRANCH.${NC}"
            echo -e "${YELLOW}[$repo_name] Use 'git stash list' and 'git stash apply' to recover your changes.${NC}"
          fi
          echo -e "${YELLOW}Staying on current branch.${NC}"
          ;;
        * )
          echo "Switching back to '$current_branch' branch."
          ;;
      esac
    fi
    
    if [ "$switch_back" = true ]; then
      git checkout "$current_branch"
      
      # Pop stash if we created one
      if [ "$stash_created" = true ]; then
        echo -e "${YELLOW}[$repo_name] Reapplying stashed changes...${NC}"
        stash_result=$(git stash pop 2>&1)
        
        if echo "$stash_result" | grep -q "CONFLICT"; then
          echo -e "${RED}[$repo_name] Conflicts occurred when reapplying stashed changes.${NC}"
          echo -e "${RED}[$repo_name] Please resolve conflicts manually.${NC}"
        else
          echo -e "${GREEN}[$repo_name] Successfully reapplied stashed changes.${NC}"
        fi
      fi
    fi
  elif [ "$stash_created" = true ] && [ "$current_branch" = "$BASE_BRANCH" ]; then
    # We're on master and stashed changes, need to apply stash
    echo -e "${YELLOW}[$repo_name] Reapplying stashed changes to $BASE_BRANCH...${NC}"
    stash_result=$(git stash pop 2>&1)
    
    if echo "$stash_result" | grep -q "CONFLICT"; then
      echo -e "${RED}[$repo_name] Conflicts occurred when reapplying stashed changes.${NC}"
      echo -e "${RED}[$repo_name] Please resolve conflicts manually.${NC}"
    else
      echo -e "${GREEN}[$repo_name] Successfully reapplied stashed changes.${NC}"
    fi
  fi
  
  # Return to original directory
  cd - > /dev/null

  # Store results in global array
  if [ $repo_index -ge 0 ]; then
    # Construct detailed result message
    local result_message=""
    
    # Add master pull info
    result_message+="${GREEN}Pulled $BASE_BRANCH${NC}\n"
    
    # Add stash info
    if [ "$stash_created" = true ]; then
      if echo "$stash_result" | grep -q "CONFLICT"; then
        result_message+="${RED}Stash conflicts: Changes were auto-stashed but had conflicts when reapplied${NC}\n"
      else
        result_message+="${GREEN}Auto-stashed: Changes were temporarily stashed and reapplied${NC}\n"
      fi
    fi
    
    # Add branch rebase info
    if [ ${#success_branches[@]} -eq 0 ] && [ ${#failed_branches[@]} -eq 0 ] && [ ${#skipped_branches[@]} -eq 0 ]; then
      result_message+="${YELLOW}No branches found to rebase${NC}\n"
    else
      # Add successful branches
      if [ ${#success_branches[@]} -gt 0 ]; then
        result_message+="${GREEN}Rebased: ${success_branches[*]}${NC}\n"
      fi
      
      # Add failed branches
      if [ ${#failed_branches[@]} -gt 0 ]; then
        result_message+="${RED}Failed: ${failed_branches[*]}${NC}\n"
      fi
      
      # Add skipped branches
      if [ ${#skipped_branches[@]} -gt 0 ]; then
        result_message+="${YELLOW}Skipped: ${skipped_branches[*]}${NC}\n"
      fi
    fi
    
    # Remove trailing newline
    result_message=$(echo -e "$result_message" | sed '$ s/\\n$//')
    
    REPO_RESULTS[$repo_index]="$result_message"
  fi
  
  return $([ "$has_conflict" = true ] && echo 1 || echo 0)
}

# Check if rebase file exists
if [ ! -f "$REBASE_FILE" ]; then
  echo -e "${YELLOW}Warning: Rebase file $REBASE_FILE does not exist. Will only pull $BASE_BRANCH for all repos.${NC}"
  echo -e "${YELLOW}To specify branches to rebase, create a file at $REBASE_FILE${NC}"
  echo -e "${YELLOW}Format: one branch per line, or 'repo:branch' to target specific repositories.${NC}"
fi

# Validate repositories list
if [ ${#REPOS[@]} -eq 0 ]; then
  echo -e "${RED}Error: No repositories specified in $CONFIG_FILE.${NC}"
  echo "Please add at least one repository path to the config file."
  exit 1
fi

# Display configuration
echo -e "${YELLOW}======= Configuration =======${NC}"
echo -e "Base branch: ${GREEN}$BASE_BRANCH${NC}"
echo -e "Auto-stashing changes: ${GREEN}Enabled${NC}"
echo -e "Force push after rebase: $([ "$FORCE_PUSH" = "true" ] && echo "${GREEN}Enabled${NC}" || echo "${YELLOW}Disabled${NC}")"
echo -e "Ask before branch switch: $([ "$ASK_BEFORE_SWITCH" = "true" ] && echo "${GREEN}Enabled${NC}" || echo "${YELLOW}Disabled${NC}")"
echo -e "Config file: ${GREEN}$CONFIG_FILE${NC}"
echo -e "Rebase file: ${GREEN}$REBASE_FILE${NC}"
echo -e "Found ${GREEN}${#REPOS[@]}${NC} repositories to update."
echo -e "${YELLOW}============================${NC}"

# Repository and branch results
# Use simple arrays instead of associative arrays for broader compatibility
REPO_NAMES=()
REPO_RESULTS=()
CONFLICT_REPOS=()
SUCCESS_REPOS=()

# Update each repository
for repo in "${REPOS[@]}"; do
  # Store repository name for result tracking
  repo_name=$(basename "$repo")
  REPO_NAMES+=("$repo_name")
  REPO_RESULTS+=("")  # Initialize with empty string, will be set in update_repo function
  
  if update_repo "$repo"; then
    SUCCESS_REPOS+=("$repo_name")
  else
    CONFLICT_REPOS+=("$repo_name")
  fi
done

# Print summary
echo -e "\n${YELLOW}=============== UPDATE SUMMARY ===============${NC}"

# First show overall status
if [ ${#SUCCESS_REPOS[@]} -gt 0 ]; then
  echo -e "${GREEN}Successfully updated repositories:${NC}"
  for repo in "${SUCCESS_REPOS[@]}"; do
    echo -e "  - $repo"
  done
fi

if [ ${#CONFLICT_REPOS[@]} -gt 0 ]; then
  echo -e "\n${RED}Repositories with issues:${NC}"
  for repo in "${CONFLICT_REPOS[@]}"; do
    echo -e "  - $repo"
  done
fi

# Then show detailed branch status for each repo
echo -e "\n${YELLOW}Detailed Results:${NC}"
for i in "${!REPO_NAMES[@]}"; do
  repo_name="${REPO_NAMES[$i]}"
  echo -e "\n${YELLOW}$repo_name:${NC}"
  # Display the stored results with proper indentation
  echo -e "${REPO_RESULTS[$i]}" | sed 's/^/  /'
done

echo -e "\n${YELLOW}==============================================${NC}"