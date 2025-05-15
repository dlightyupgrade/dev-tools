# Personal Development Tools

A collection of personal development tools and utilities for improving development workflows.

## Tools

### Local LLM Git Tools

A set of tools that use local LLM (via Ollama) to improve Git workflows without sending code to external services.

- `cli/llm_commit` - Generate meaningful commit messages using a local LLM
- `cli/llm_pr` - Create high-quality PR descriptions using a local LLM
- `cli/llm_setup` - Setup script for checking dependencies and downloading models

[Read more about the LLM Git Tools](cli/README-llm-git.md)

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

## Requirements

Different tools have different requirements. See the specific tool's README for details.

For the LLM Git Tools:
- Git
- Python 3.6+
- [Ollama](https://ollama.ai/) for local LLM inference
- GitHub CLI (`gh`) for PR creation