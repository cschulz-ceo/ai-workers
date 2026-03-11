# Agent Skills

Skills are reusable capability packages that agents load to perform specialized tasks.
Each skill is a subdirectory containing a prompt template, required tools, and usage notes.

## Structure
```
skills/
└── <skill-name>/
    ├── README.md       — What this skill does and when to use it
    ├── prompt.md       — System prompt / instructions for the skill
    └── tools.json      — MCP tools this skill requires
```

## Available Skills
(None yet — add skills as agents are built out)
