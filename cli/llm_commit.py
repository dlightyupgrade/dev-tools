#!/usr/bin/env python3
"""
Local LLM Git Commit Assistant

This script uses a local LLM (via Ollama) to generate commit messages
based on git diffs. It extracts git diff information, passes it to a
local LLM model, and uses the generated message for a git commit.

Usage:
  llm_commit.py [options]

Basic Options:
  -h, --help            Show this help message and exit
  -m MODEL, --model MODEL
                        Specify the Ollama model to use (default: phi3:mini)
  -e, --edit            Edit the generated commit message before committing
  -d, --dry-run         Show the generated commit message without committing
  -v, --verbose         Show verbose output including the diff and prompt
  -s STYLE, --style STYLE
                        Commit message style (conventional, compact, detailed, concise)
                        - conventional: Standard format <type>(<scope>): <description>
                        - compact: Ultra-short messages (max 30 chars)
                        - concise: Single line brief summary
                        - detailed: Full commit with description
  -p, --prefix          Add a ticket ID prefix from the branch name (e.g., SI-1234)
  --push                Automatically push changes after commit
  -y, --yes             Skip confirmation prompts and commit directly

Branch Creation Options:
  -b BRANCH, --branch BRANCH
                        Create or switch to this branch before committing

PR Creation Options:
  --pr                  Create a PR after committing and pushing
  --base BASE           Base branch for PR (default: main)
  --pr-edit             Edit the PR description before submitting

Examples:
  # Create a branch, commit changes, and create a PR in one command
  llm_commit -b feature/new-feature --pr

  # Create a compact commit message with automatic push
  llm_commit -s compact --push

  # Create a commit with a specific LLM model and ticket prefix
  llm_commit -m codellama:7b -p

By default, the tool will:
  1. Generate a commit message based on staged changes
  2. Ask for confirmation before committing
  3. Ask if you want to push the changes after committing

Requirements:
  - Git installed and available in PATH
  - Ollama installed and running
  - GitHub CLI (gh) installed for PR creation
  - Python 3.6+
  - Requests library (pip install requests)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from subprocess import PIPE, run

try:
    import requests
except ImportError:
    print("Error: requests library not installed. Please run 'pip install requests'")
    sys.exit(1)

OLLAMA_API_URL = "http://localhost:11434/api/generate"
DEFAULT_MODEL = "phi3:mini"
DEFAULT_STYLE = "conventional"

# ANSI color codes
BLUE = "\033[94m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
ENDC = "\033[0m"
BOLD = "\033[1m"

def print_colored(text, color):
    """Print colored text"""
    print(f"{color}{text}{ENDC}")

def check_dependencies():
    """Check if all required dependencies are installed"""
    # Check git
    try:
        run(["git", "--version"], stdout=PIPE, stderr=PIPE, check=True)
    except (subprocess.SubprocessError, FileNotFoundError):
        print_colored("Error: Git is not installed or not available in PATH", RED)
        sys.exit(1)
    
    # Check Ollama server
    try:
        response = requests.get("http://localhost:11434/api/tags")
        if response.status_code != 200:
            print_colored("Error: Ollama server is not running. Start it with 'ollama serve'", RED)
            sys.exit(1)
    except requests.exceptions.ConnectionError:
        print_colored("Error: Cannot connect to Ollama server at http://localhost:11434", RED)
        print_colored("Make sure Ollama is installed and running with 'ollama serve'", RED)
        sys.exit(1)

def get_git_diff():
    """Get the git diff for staged changes"""
    result = run(["git", "diff", "--staged"], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        print_colored(f"Error getting git diff: {result.stderr}", RED)
        sys.exit(1)
    
    # If no staged changes, check if there are unstaged changes
    if not result.stdout.strip():
        unstaged_result = run(["git", "diff"], stdout=PIPE, stderr=PIPE, text=True)
        if unstaged_result.stdout.strip():
            print_colored("No staged changes found. There are unstaged changes available.", YELLOW)
            choice = input("Would you like to stage all changes? [y/N]: ")
            if choice.lower() == 'y':
                run(["git", "add", "."], stdout=PIPE, stderr=PIPE, check=True)
                return get_git_diff()
            else:
                print_colored("No changes staged for commit. Exiting.", YELLOW)
                sys.exit(0)
        else:
            print_colored("No changes (staged or unstaged) found. Exiting.", YELLOW)
            sys.exit(0)
    
    return result.stdout

def get_changed_files():
    """Get a list of changed files in the staging area"""
    result = run(["git", "diff", "--staged", "--name-only"], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        print_colored(f"Error getting changed files: {result.stderr}", RED)
        sys.exit(1)
    
    return result.stdout.strip().split('\n')

def extract_ticket_from_branch():
    """Extract ticket ID from branch name (e.g., feature/SI-1234-description)"""
    result = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        return None
    
    branch_name = result.stdout.strip()
    
    # Look for common ticket formats
    # Examples: SI-1234, JIRA-5678, ABC-901
    match = re.search(r'(?:^|[/-])([A-Z]+-\d+)', branch_name)
    if match:
        return match.group(1)
    
    # Check if it's a nojira branch
    if 'nojira' in branch_name.lower():
        return 'NOJIRA'
    
    return None

def create_prompt(diff, style, files):
    """Create the prompt for the LLM based on the diff and style"""
    if style == "conventional":
        prompt_template = """
You are a helpful assistant that generates high-quality git commit messages in the Conventional Commits format.

Based on the diff below, write a VERY CONCISE and informative commit message in the format:
<type>(<scope>): <description>

Where:
- type: feat, fix, docs, style, refactor, test, chore, etc.
- scope: optional area affected (e.g., component name, file type)
- description: concise description of the change in imperative mood (UNDER 50 CHARACTERS TOTAL)

Do not include a body or footer section. Focus on WHY the change was made, not WHAT was changed.
BE EXTREMELY BRIEF - the entire message should be under 50 characters if possible.
Return ONLY the commit message, nothing else.

Changed files:
{}

Diff:
{}
"""
    elif style == "compact":
        prompt_template = """
You are a helpful assistant that generates extremely short git commit messages.

Based on the diff below, write an ULTRA-COMPACT commit message:
- MAXIMUM 30 CHARACTERS TOTAL
- Use imperative mood (e.g., "Add", "Fix", "Update", "Remove")
- Focus on the core purpose of the change
- Be specific but extremely brief
- No punctuation at the end

Return ONLY the commit message, nothing else.

Changed files:
{}

Diff:
{}
"""
    elif style == "detailed":
        prompt_template = """
You are a helpful assistant that generates high-quality git commit messages with detailed explanations.

Based on the diff below, write an informative commit message with:
1. A short, specific summary line (50-72 chars)
2. A detailed description explaining WHY the change was made
3. Any important context or implications

Return ONLY the commit message, nothing else.

Changed files:
{}

Diff:
{}
"""
    else:  # concise
        prompt_template = """
You are a helpful assistant that generates concise git commit messages.

Based on the diff below, write a single line, concise and informative commit message.
- Keep the message under 60 characters
- Focus on WHY the change was made, not WHAT was changed
- Use imperative mood, as if giving a command
- No description or body text

Return ONLY the commit message, nothing else.

Changed files:
{}

Diff:
{}
"""
    
    files_text = "\n".join(files)
    return prompt_template.format(files_text, diff)

def generate_commit_message(prompt, model):
    """Generate a commit message using the Ollama API"""
    print_colored(f"Generating commit message using Ollama ({model})...", BLUE)
    
    data = {
        "model": model,
        "prompt": prompt,
        "stream": False
    }
    
    try:
        response = requests.post(OLLAMA_API_URL, json=data)
        response.raise_for_status()
        result = response.json()
        message = result.get("response", "").strip()
        
        # Post-process the message to keep it concise
        # If it has multiple lines, keep just the first line
        if "\n" in message:
            first_line = message.split("\n")[0].strip()
            if first_line:
                message = first_line
        
        # Remove any trailing punctuation
        message = message.rstrip(".!?,;:")
        
        return message
    except requests.exceptions.RequestException as e:
        print_colored(f"Error communicating with Ollama API: {e}", RED)
        # Check if the model is not available
        if hasattr(e, 'response') and e.response and e.response.status_code == 404:
            print_colored(f"\nModel '{model}' not found.", RED)
            print_colored(f"Try pulling it with: ollama pull {model}", YELLOW)
        sys.exit(1)

def edit_message(message):
    """Open an editor to allow the user to edit the generated message"""
    with tempfile.NamedTemporaryFile(suffix=".tmp", mode="w+", delete=False) as tf:
        tf.write(message)
        tf_name = tf.name
    
    editor = os.environ.get('EDITOR', 'vim')
    subprocess.call([editor, tf_name])
    
    with open(tf_name, 'r') as tf:
        edited_message = tf.read()
    
    os.unlink(tf_name)
    return edited_message

def create_commit(message, auto_push=False):
    """Create a git commit with the generated message"""
    # Ask for confirmation
    print_colored("\nReady to commit with message:", GREEN)
    print(f"{BOLD}{message}{ENDC}")
    
    choice = input("\nCreate commit? [Y/n]: ")
    if choice.lower() == 'n':
        print_colored("Commit cancelled.", YELLOW)
        return
    
    result = run(["git", "commit", "-m", message], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        print_colored(f"Error creating commit: {result.stderr}", RED)
        sys.exit(1)
    
    print_colored("\nCommit created successfully:", GREEN)
    print(result.stdout)
    
    # Ask if user wants to push
    if auto_push:
        push_changes()
    else:
        choice = input("\nPush changes to remote? [y/N]: ")
        if choice.lower() == 'y':
            push_changes()

def get_current_branch():
    """Get the name of the current git branch"""
    branch_result = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], stdout=PIPE, stderr=PIPE, text=True)
    if branch_result.returncode != 0:
        print_colored(f"Error getting current branch: {branch_result.stderr}", RED)
        return None
    return branch_result.stdout.strip()

def create_branch(branch_name):
    """Create a new git branch and switch to it"""
    print_colored(f"\nCreating new branch: {branch_name}", BLUE)
    
    # Check if branch already exists
    check_result = run(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch_name}"], 
                       stdout=PIPE, stderr=PIPE)
    
    if check_result.returncode == 0:
        print_colored(f"Branch '{branch_name}' already exists.", YELLOW)
        
        # Ask if user wants to switch to existing branch
        choice = input(f"Switch to existing branch '{branch_name}'? [Y/n]: ")
        if choice.lower() == 'n':
            print_colored("Branch creation cancelled.", YELLOW)
            return False
        
        # Checkout existing branch
        checkout_result = run(["git", "checkout", branch_name], stdout=PIPE, stderr=PIPE, text=True)
        if checkout_result.returncode != 0:
            print_colored(f"Error switching to branch: {checkout_result.stderr}", RED)
            return False
        
        print_colored(f"Switched to existing branch '{branch_name}'", GREEN)
        return True
    
    # Create and checkout new branch
    result = run(["git", "checkout", "-b", branch_name], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        print_colored(f"Error creating branch: {result.stderr}", RED)
        return False
    
    print_colored(f"Created and switched to new branch '{branch_name}'", GREEN)
    return True

def push_changes():
    """Push changes to remote repository"""
    print_colored("\nPushing changes to remote...", BLUE)
    
    # Get the current branch
    current_branch = get_current_branch()
    if not current_branch:
        return False
    
    # Push changes
    result = run(["git", "push", "-u", "origin", current_branch], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        print_colored(f"Error pushing changes: {result.stderr}", RED)
        return False
    
    print_colored("\nChanges pushed successfully:", GREEN)
    print(result.stdout)
    return True

def create_pr(model=DEFAULT_MODEL, edit=False, base_branch="main"):
    """Create a PR using the llm_pr script"""
    print_colored("\nCreating PR...", BLUE)
    
    # Get the directory of this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Build the command to run llm_pr
    cmd = [os.path.join(script_dir, "llm_pr")]
    
    # Add options
    if model != DEFAULT_MODEL:
        cmd.extend(["-m", model])
    if edit:
        cmd.append("-e")
    if base_branch != "main":
        cmd.extend(["-b", base_branch])
    
    print_colored(f"Running: {' '.join(cmd)}", BLUE)
    
    # First, make sure the base branch exists or can be fetched
    check_base_branch(base_branch)
    
    # Run the llm_pr script
    try:
        # Use subprocess.run with text=True for better error handling
        pr_result = subprocess.run(cmd, capture_output=True, text=True)
        
        # Print the output regardless of success/failure
        if pr_result.stdout:
            print(pr_result.stdout)
        
        if pr_result.returncode != 0:
            if pr_result.stderr:
                print_colored(f"Error output from PR creation:", RED)
                print(pr_result.stderr)
            print_colored("Error creating PR. See details above.", RED)
            return False
        
        return True
    except Exception as e:
        print_colored(f"Error creating PR: {e}", RED)
        return False

def check_base_branch(base_branch):
    """Check if base branch exists, try to fetch it if not"""
    # Check if branch exists locally
    check_result = run(["git", "rev-parse", "--verify", "--quiet", base_branch], 
                     stdout=PIPE, stderr=PIPE)
    
    if check_result.returncode != 0:
        print_colored(f"Base branch '{base_branch}' not found locally. Attempting to fetch...", YELLOW)
        
        # Try to get default remote
        remote_result = run(["git", "remote"], stdout=PIPE, stderr=PIPE, text=True)
        
        if remote_result.returncode != 0 or not remote_result.stdout.strip():
            print_colored("No remote repository found. Please add a remote first.", RED)
            return False
        
        default_remote = remote_result.stdout.strip().split("\n")[0]
        
        # Try to fetch the branch
        fetch_cmd = ["git", "fetch", default_remote, f"{base_branch}:{base_branch}"]
        fetch_result = run(fetch_cmd, stdout=PIPE, stderr=PIPE, text=True)
        
        if fetch_result.returncode == 0:
            print_colored(f"Successfully fetched '{base_branch}' from remote.", GREEN)
            return True
        else:
            print_colored(f"Could not fetch '{base_branch}' from remote. PR may have limited context.", YELLOW)
            print_colored("PR creation will continue, but may not include complete commit history.", YELLOW)
            return False
    
    return True

def main():
    parser = argparse.ArgumentParser(description='Generate git commit messages using a local LLM')
    parser.add_argument('-m', '--model', default=DEFAULT_MODEL,
                      help=f'Specify the Ollama model to use (default: {DEFAULT_MODEL})')
    parser.add_argument('-e', '--edit', action='store_true',
                      help='Edit the generated commit message before committing')
    parser.add_argument('-d', '--dry-run', action='store_true',
                      help='Show the generated commit message without committing')
    parser.add_argument('-v', '--verbose', action='store_true',
                      help='Show verbose output including the diff and prompt')
    parser.add_argument('-s', '--style', default=DEFAULT_STYLE, 
                      choices=['conventional', 'compact', 'detailed', 'concise'],
                      help='Commit message style (default: conventional, compact=ultra short)')
    parser.add_argument('-p', '--prefix', action='store_true',
                      help='Add a ticket ID prefix from the branch name')
    parser.add_argument('--push', action='store_true',
                      help='Automatically push changes after commit')
    parser.add_argument('-y', '--yes', action='store_true',
                      help='Skip confirmation prompts and commit directly')
    
    # Branch creation options
    branch_group = parser.add_argument_group('Branch Creation')
    branch_group.add_argument('-b', '--branch', 
                      help='Create or switch to this branch before committing')
    
    # PR creation options
    pr_group = parser.add_argument_group('PR Creation')
    pr_group.add_argument('--pr', action='store_true',
                      help='Create a PR after committing and pushing')
    pr_group.add_argument('--base', default='main',
                      help='Base branch for PR (default: main)')
    pr_group.add_argument('--pr-edit', action='store_true',
                      help='Edit the PR description before submitting')
    
    args = parser.parse_args()
    
    try:
        # Check dependencies
        check_dependencies()
        
        # Create or switch to branch if requested
        if args.branch:
            if not create_branch(args.branch):
                print_colored("Failed to create or switch to branch. Exiting.", RED)
                sys.exit(1)
        
        # Get git diff
        diff = get_git_diff()
        files = get_changed_files()
        
        if args.verbose:
            print_colored("\nChanged files:", BLUE)
            for file in files:
                print(f"  {file}")
            print_colored("\nDiff:", BLUE)
            print(diff)
        
        # Create prompt
        prompt = create_prompt(diff, args.style, files)
        
        if args.verbose:
            print_colored("\nPrompt:", BLUE)
            print(prompt)
        
        # Generate commit message
        message = generate_commit_message(prompt, args.model)
        
        # Add ticket prefix if requested
        if args.prefix:
            ticket = extract_ticket_from_branch()
            if ticket:
                # Check if message already contains the ticket
                if not re.search(rf'\b{re.escape(ticket)}\b', message):
                    message = f"{ticket}: {message}"
        
        # Display generated message
        print_colored("\nGenerated commit message:", GREEN)
        print(f"{BOLD}{message}{ENDC}")
        
        # Edit message if requested
        if args.edit:
            print_colored("\nOpening editor for you to modify the commit message...", BLUE)
            message = edit_message(message)
            print_colored("\nUpdated commit message:", GREEN)
            print(f"{BOLD}{message}{ENDC}")
        
        # Create commit if not dry-run
        commit_success = False
        if not args.dry_run:
            if args.yes:
                # Skip confirmation and commit directly
                print_colored("\nCreating commit...", BLUE)
                result = run(["git", "commit", "-m", message], stdout=PIPE, stderr=PIPE, text=True)
                if result.returncode != 0:
                    print_colored(f"Error creating commit: {result.stderr}", RED)
                    sys.exit(1)
                
                print_colored("\nCommit created successfully:", GREEN)
                print(result.stdout)
                commit_success = True
                
                # Push if requested
                push_success = False
                if args.push or args.pr:
                    push_success = push_changes()
                
                # Create PR if requested
                if args.pr and push_success:
                    create_pr(model=args.model, edit=args.pr_edit, base_branch=args.base)
            else:
                # Use interactive commit with confirmation
                create_commit(message, args.push)
                commit_success = True
                
                # Create PR if requested and not already pushed
                if args.pr and commit_success and not args.push:
                    choice = input("\nCreate PR? [y/N]: ")
                    if choice.lower() == 'y':
                        # Push changes first if needed
                        if push_changes():
                            create_pr(model=args.model, edit=args.pr_edit, base_branch=args.base)
                elif args.pr and commit_success and args.push:
                    # We already pushed from create_commit, so just create the PR
                    choice = input("\nCreate PR? [y/N]: ")
                    if choice.lower() == 'y':
                        create_pr(model=args.model, edit=args.pr_edit, base_branch=args.base)
        else:
            print_colored("\nDry run - no commit created", YELLOW)
    
    except KeyboardInterrupt:
        print_colored("\nOperation cancelled by user", YELLOW)
        sys.exit(0)

if __name__ == "__main__":
    main()