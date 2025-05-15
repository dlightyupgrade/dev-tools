#!/usr/bin/env python3
"""
Helper script to extract prompt templates for the bash scripts.
"""

from pr_prompts import STANDARD_PR_PROMPT, FALLBACK_PR_PROMPT

def output_prompt(name, prompt):
    """Output a prompt template to a file"""
    with open(f"{name}.prompt", "w") as f:
        f.write(prompt)

if __name__ == "__main__":
    # Extract PR prompts to files in the current directory
    output_prompt("standard_pr", STANDARD_PR_PROMPT)
    output_prompt("fallback_pr", FALLBACK_PR_PROMPT)
    
    print("Prompt templates extracted to .prompt files")