# Personal Development Tools

A collection of personal development tools and utilities for improving development workflows.

## Tools

### Local LLM Git Tools

A set of tools that use local LLM (via Ollama) to improve Git workflows without sending code to external services.

- `cli/llm_commit` - Generate meaningful commit messages using a local LLM
- `cli/llm_pr` - Create high-quality PR descriptions using a local LLM
- `cli/llm_setup` - Setup script for checking dependencies and downloading models
- `cli/claude_commit` - Generate commit messages using Claude API

[Read more about the LLM Git Tools](cli/README-llm-git.md)

### Repository Management Tools

Tools for managing multiple repositories and streamlining development workflows.

- `cli/update-core-repos.sh` - Update multiple repositories, pulling latest master and rebasing branches
- `cli/review-prs.sh` - Script for reviewing and managing pull requests

[Read more about the Repo Updater](cli/README-update-core-repos.md)

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/dlightyupgrade/dev-tools.git personal-dev-tools
   cd personal-dev-tools
   ```

2. Run the setup script for specific tools:
   ```
   # For LLM Git Tools
   cd cli
   ./llm_setup
   ```

3. Add tool aliases to your .zshrc/.bashrc (examples):
   ```bash
   # PR Status Script
   alias -g prr="~/code/personal-dev-tools/cli/review-prs.sh"
   # Local LLM Git Tools
   alias -g ggc="~/code/personal-dev-tools/cli/llm_commit"
   alias -g ggpr="~/code/personal-dev-tools/cli/llm_pr"
   alias -g lsu="~/code/personal-dev-tools/cli/llm_setup"
   # Repo update script
   alias -g pru="~/code/personal-dev-tools/cli/update-core-repos.sh"
   # Claude integration
   alias -g cc="~/code/personal-dev-tools/cli/claude_commit"
   ```

## Requirements

Different tools have different requirements. See the specific tool's README for details.

For the LLM Git Tools:
- Git
- Python 3.6+
- [Ollama](https://ollama.ai/) for local LLM inference
- GitHub CLI (`gh`) for PR creation

For the Claude integration:
- Anthropic Claude API key
- Python 3.6+
- `anthropic` Python package

For the Repository Management Tools:
- Git
- GitHub CLI (`gh`) for PR management