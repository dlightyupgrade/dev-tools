"""
Prompt templates for the LLM Git Commit Assistant.

This file contains the prompt templates used by the llm_commit tool to generate
commit messages in different styles. Users can modify these templates to customize
the style and content of generated commit messages.
"""

# Conventional Commits style prompt
CONVENTIONAL_PROMPT = """
You will act as a git commit message generator. When receiving a git diff, you will ONLY output the commit message itself, nothing else. No explanations, no questions, no additional comments.

Based on the diff below, write a VERY CONCISE and informative commit message in the format:
[optional emoji] <type>(<scope>): <description>

Where:
- type: feat, fix, docs, style, refactor, test, chore, etc.
- scope: optional area affected (e.g., component name, file type)
- description: concise description of the change(s)

Do not include a body or footer section. Focus on WHY the change was made, not WHAT was changed.
Do not include any code samples.
BE EXTREMELY BRIEF - the entire message should be under 50 characters if possible.
Return ONLY the commit message, nothing else.

This should be written from the point-of-view of the developer (e.g., Here are changes that)
This should not have language like "It seems" or "Having reviewed"
It should be a bulleted list of changes
It should be markdown formatted

Only return the commit message.

Changed files:
{}

Diff:
{}
"""

# Compact style prompt (ultra-short)
COMPACT_PROMPT = """
You are a helpful assistant that generates extremely short git commit messages.

Based on the diff below, write an ULTRA-COMPACT commit message:
- MAXIMUM 30 CHARACTERS TOTAL
- Use imperative mood (e.g., "Add", "Fix", "Update", "Remove")
- Focus on the core purpose of the change
- Be specific but extremely brief
- No punctuation at the end

Do not include a body or footer section. Focus on WHY the change was made, not WHAT was changed.
Do not include any code samples.
Do not explain yourself, do not give choices about commit messages

Based on the diff below, write a VERY CONCISE and informative commit message in the format:

Give me only the actual commit message that will be used in a script to auto commit.

Changed files:
{}

Diff:
{}
"""

# Detailed style prompt (with more information)
DETAILED_PROMPT = """
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

# Concise style prompt (brief but informative)
CONCISE_PROMPT = """
You are a helpful assistant that generates concise git commit messages.

Based on the diff below, write a single line, concise and informative commit message.
- Keep the message under 60 characters
- Focus on WHY the change was made, not WHAT was changed
- Use imperative mood, as if giving a command
- No description or body text

Return ONLY the commit message, nothing else.
It should be markdown formatted

Changed files:
{}

Diff:
{}
"""

# Dictionary mapping style names to prompts
PROMPT_MAP = {
    "conventional": CONVENTIONAL_PROMPT,
    "compact": COMPACT_PROMPT,
    "detailed": DETAILED_PROMPT,
    "concise": CONCISE_PROMPT
}