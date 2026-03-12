# claude-dev-tools

Reusable AI-powered development tooling for multi-agent workflows using Claude Code CLI.

## Quick Start

### Option A: Git submodule (recommended)

```bash
cd your-project
git submodule add git@github.com:your-org/claude-dev-tools.git tools/devtools
bash tools/devtools/install.sh
```

### Option B: Clone alongside project

```bash
git clone git@github.com:your-org/claude-dev-tools.git
cd your-project
bash ../claude-dev-tools/install.sh
export PATH="../claude-dev-tools/bin:$PATH"
```

## Setup

1. Edit `.devtools.yaml` with your project settings
2. Create `.devtools/agents/` overrides for project-specific prompts (optional)
3. Run tools: `devtools relay-race`, `devtools review-pr`, etc.

## Tools

| Command | Description |
|---------|-------------|
| `relay-race` | Multi-agent parallel task runner with dependency management |
| `fix-loop` | Automated PR review + fix + re-review loop |
| `review-pr` | 4-reviewer parallel PR review |
| `lane` | Docker container management for isolated dev lanes |
| `pr-watch` | CI check watcher with failure reporting |
| `opus-plan` | Opus planning agent wrapper |
| `screenshot` | Playwright page screenshot utility |
| `pick-browser-tests` | AI-driven browser test selection |
| `run-browser-tests` | Browser-use test runner (Python/Pytest) |
| `ask-gemini` | Gemini CLI/SDK wrapper |

## Agent Overrides

Built-in agent prompts live in `agents/*.md`. Override any agent by placing
a file with the same name in your project's `.devtools/agents/` directory.

Example: To customize the review correctness prompt:
```bash
cp agents/review-correctness.md .devtools/agents/review-correctness.md
# Edit to add project-specific rules
```

## Configuration

See `.devtools.yaml.example` for all configuration options.

## Requirements

- `claude` CLI (authenticated via Claude Code subscription)
- `gh` CLI (authenticated for PR operations)
- `jq` (JSON processing)
- `git` (2.0+)
- `bash` (4.3+ for parallel relay, 3.2+ for sequential)
- `docker` (for lane containers, optional)
- `python3` + `pytest` (for browser-use tests, optional)
