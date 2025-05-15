"""
Prompt templates for the LLM Git PR Assistant.

This file contains the prompt templates used by the llm_pr tool to generate
PR descriptions. Users can modify these templates to customize the style and 
content of generated PR descriptions.
"""

# Standard PR description prompt with commit history
STANDARD_PR_PROMPT = """
You are a helpful assistant that generates high-quality GitHub PR descriptions.

Based on the following commits and changes, write a detailed PR description that includes:

1. A clear summary of what this PR does
2. Key changes and their purpose
3. Any important implementation details
4. Testing instructions if applicable

Format the response as markdown with appropriate headers and bullet points.
Return ONLY the PR description, nothing else.

# Commits
{}

# Diff Summary
{}
"""

# PR description prompt when commit history isn't available
FALLBACK_PR_PROMPT = """
You are a helpful assistant that generates high-quality GitHub PR descriptions.

Based on the following information, write a detailed PR description that includes:

1. A clear summary of what this PR appears to do (based on recent commits and changes)
2. The purpose of the changes, as best as can be determined
3. Any implementation details visible from the diffs and commits
4. General testing instructions

Format the response as markdown with appropriate headers and bullet points.
Return ONLY the PR description, nothing else.

# Recent Commits on This Branch
{}

# Current Changes
{}
"""