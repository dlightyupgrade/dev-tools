#!/usr/bin/env python3
"""
Local LLM Git Commit Assistant

This script uses a local LLM (via Ollama) to generate commit messages
based on git diffs. It extracts git diff information, passes it to a
local LLM model, and uses the generated message for a git commit.

Usage:
  llm_commit.py [options]

Options:
  -h, --help            Show this help message and exit
  -m MODEL, --model MODEL
                        Specify the Ollama model to use (default: phi3:mini)
  -e, --edit            Edit the generated commit message before committing
  -d, --dry-run         Show the generated commit message without committing
  -v, --verbose         Show verbose output including the diff and prompt
  -s STYLE, --style STYLE
                        Commit message style (conventional, detailed, concise)
  -p, --prefix          Add a ticket ID prefix from the branch name (e.g., SI-1234)

Requirements:
  - Git installed and available in PATH
  - Ollama installed and running
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

Based on the diff below, write a concise and informative commit message in the format:
<type>(<scope>): <description>

Where:
- type: feat, fix, docs, style, refactor, test, chore, etc.
- scope: optional area affected (e.g., component name, file type)
- description: concise description of the change in imperative mood

Do not include a body or footer section. Focus on WHY the change was made, not WHAT was changed.
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
You are a helpful assistant that generates high-quality git commit messages.

Based on the diff below, write a single line, concise and informative commit message.
Focus on WHY the change was made, not WHAT was changed.
Use imperative mood, as if giving a command.
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

def create_commit(message):
    """Create a git commit with the generated message"""
    result = run(["git", "commit", "-m", message], stdout=PIPE, stderr=PIPE, text=True)
    if result.returncode != 0:
        print_colored(f"Error creating commit: {result.stderr}", RED)
        sys.exit(1)
    
    print_colored("\nCommit created successfully:", GREEN)
    print(result.stdout)

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
                      choices=['conventional', 'detailed', 'concise'],
                      help='Commit message style (default: conventional)')
    parser.add_argument('-p', '--prefix', action='store_true',
                      help='Add a ticket ID prefix from the branch name')
    
    args = parser.parse_args()
    
    try:
        # Check dependencies
        check_dependencies()
        
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
        if not args.dry_run:
            print_colored("\nCreating commit...", BLUE)
            create_commit(message)
        else:
            print_colored("\nDry run - no commit created", YELLOW)
    
    except KeyboardInterrupt:
        print_colored("\nOperation cancelled by user", YELLOW)
        sys.exit(0)

if __name__ == "__main__":
    main()