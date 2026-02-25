"""Droid resolution: agent_type → (display_name, color, emoji)"""

DROID_MAP: dict[str, tuple[str, str, str]] = {
    "jira-analyst":                  ("jira-analyst",                  "#3B82F6", "🤖"),
    "java-code-reviewer":            ("java-code-reviewer",            "#EF4444", "⚕️"),
    "architecture-reviewer":         ("architecture-reviewer",         "#8B5CF6", "🏛️"),
    "agent-builder":                 ("agent-builder",                 "#F59E0B", "🔧"),
    "test-generator":                ("test-generator",                "#10B981", "🧪"),
    "coverage-analyzer":             ("coverage-analyzer",             "#06B6D4", "📊"),
    "database-migration-specialist": ("database-migration-specialist", "#84CC16", "🗄️"),
    "java-minimizer":                ("java-minimizer",                "#F97316", "⚡"),
    "comprehensive-reviewer":        ("comprehensive-reviewer",        "#EC4899", "🔍"),
    "confluence-spec-manager":       ("confluence-spec-manager",       "#A78BFA", "📚"),
    "c3po":                          ("c3po",                          "#FBBF24", "📖"),
    "claude-code-guide":             ("claude-code-guide",             "#FBBF24", "📖"),
    "general-purpose":               ("general-purpose",               "#6B7280", "⚙️"),
    "Explore":                       ("Explore",                       "#34D399", "🔭"),
    "Plan":                          ("Plan",                          "#60A5FA", "📐"),
}

UNKNOWN_DROID = ("???", "#6B7280", "❓")


def resolve_droid(agent_type: str | None) -> tuple[str, str, str]:
    """Return (display_name, color, emoji) for the given agent_type string."""
    if not agent_type:
        return UNKNOWN_DROID
    # Strip plugin prefix: "servicing-plugin:java-code-reviewer" → "java-code-reviewer"
    key = agent_type.split(":")[-1] if ":" in agent_type else agent_type
    # Use the key itself as the display name (falls back gracefully for unknown types)
    color_emoji = DROID_MAP.get(key)
    if color_emoji:
        return color_emoji
    # Unknown type: use the key as name with default styling
    return (key, "#6B7280", "⚙️")
