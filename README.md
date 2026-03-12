# claude-dev-tools

Reusable AI-powered development tooling for multi-agent workflows using Claude Code CLI.

## Quick Start

### Option A: Git submodule (recommended)

```bash
cd your-project
git submodule add git@github.com:your-org/claude-dev-tools.git tools/devtools
bash tools/devtools/install.sh
# Edit .devtools.yaml with your project settings
```

### Option B: Clone alongside project

```bash
git clone git@github.com:your-org/claude-dev-tools.git
cd your-project
bash ../claude-dev-tools/install.sh
export PATH="../claude-dev-tools/bin:$PATH"
```

## Tools

| Command | Description |
|---------|-------------|
| `relay-race` | Multi-agent parallel task runner with dependency management and quality gates |
| `review-pr` | 5-reviewer parallel PR review (correctness, complexity, test coverage, file org, security) |
| `fix-loop` | Automated review + fix + re-review loop until clean |
| `describe-pr` | Auto-generate PR title, summary, and labels from diff |
| `lane` | Docker container management for isolated dev lanes |
| `pr-watch` | CI check watcher with failure reporting |
| `opus-plan` | Opus planning agent wrapper |
| `screenshot` | Playwright page screenshot utility |
| `pick-browser-tests` | AI-driven browser test selection based on git diff |
| `run-browser-tests` | Browser-use test runner (Python/Pytest) |
| `ask-gemini` | Gemini CLI/SDK wrapper for bulk file analysis |

## Relay Race

The core tool. Breaks work into tasks, runs them in parallel with fresh agent contexts, and validates with quality gates.

```bash
relay-race                        # sequential, creates PR
relay-race --parallel 3           # 3 concurrent agents
relay-race --dry-run              # preview execution plan
relay-race --skip-review          # skip Opus review gate
relay-race --skip-static-analysis # skip deterministic lint/typecheck
```

### Quality Gates

Run automatically after tasks complete:

| Gate | Type | What it does |
|------|------|-------------|
| Static analysis | Deterministic | tsc, eslint, prettier on changed files (auto-fixes what it can) |
| Code Simplifier | Haiku | Flags dead code, duplication, oversized functions |
| Test Review | Sonnet | Writes missing tests, runs test suite |
| Hygiene | Haiku | Checks rules file size, doc clutter, broken refs |
| Opus Review | Opus | Reviews full diff against project rules, fixes violations in-place |
| Visual Critique | Sonnet vision | Screenshots affected pages, flags UI regressions |

### Duration Tracking

Every LLM invocation logs wall-clock time to `.relay-locks/duration-report.jsonl`. The PR body includes a summary of total invocations and wall time.

## PR Review

5 reviewers run in parallel, each posting to GitHub:

| Reviewer | Model | Focus |
|----------|-------|-------|
| Correctness | Sonnet | Bugs, error handling, data integrity, rules violations |
| Complexity | Opus | Overengineering, scope creep, unnecessary abstractions |
| Test Coverage | Sonnet | Missing tests for changed code |
| File Organization | Sonnet | Structural problems, repo hygiene |
| Security | Sonnet | Injection, secrets, auth, CSRF, data exposure |

```bash
review-pr 42              # review PR #42
review-pr --incremental 42  # only review new commits since last review
review-pr --skip-security 42  # skip security reviewer
review-pr --approve 42    # auto-approve if no issues
```

### Features

- **Incremental review**: Tracks last-reviewed SHA via PR comment. `--incremental` diffs from that SHA instead of PR base.
- **80/20 RAG context**: Greps for callers/importers of changed files and includes them as reviewer context (capped at 25% of context budget).
- **Diff-aware budgeting**: Prioritizes high-churn files for full content; low-churn files get diff-only when context budget is tight.
- **Review effort scoring**: Each reviewer outputs a `review_effort` (1-5) and `security_concerns` flag.

## Fix Loop

Automated review + fix cycle:

```bash
fix-loop 42               # review + fix PR #42
fix-loop 42 --no-merge    # don't auto-merge after approval
fix-loop 42 --review-only # review without auto-fixing
```

Round 1 runs all 5 reviewers. Rounds 2+ run correctness only. After 3 rounds, a meta-reviewer decides whether to continue, approve, or escalate.

## GitHub Action

Auto-review PRs on open/push:

```yaml
# .github/workflows/ai-review.yml
name: AI PR Review
on:
  pull_request:
    types: [opened, synchronize]
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0
      - run: npm install -g @anthropic-ai/claude-code
      - run: bash tools/devtools/bin/review-pr --incremental ${{ github.event.pull_request.number }}
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

See `examples/github-review-workflow.yml` for the full example.

## Agent Overrides

Built-in agent prompts live in `agents/*.md`. Override any agent by placing a file with the same name in your project's `.devtools/agents/` directory.

```bash
# Example: customize the planner for your project
cp agents/planner.md .devtools/agents/planner.md
# Edit to add project-specific context
```

## Configuration

All config lives in `.devtools.yaml` at your project root. See `.devtools.yaml.example` for all options.

Key sections:
- `project` — test/build/dev commands
- `static_analysis` — typecheck, lint, format commands for the deterministic gate
- `review` — rules file path and max lines
- `relay` — tasks file and lock directory
- `lane` — Docker image and worktree settings
- `browser_tests` — manifest, smoke tests, required env vars

## Requirements

- `claude` CLI (authenticated via Claude Code subscription or API key)
- `gh` CLI (authenticated for PR operations)
- `jq` (JSON processing)
- `git` (2.0+)
- `bash` (4.3+ for parallel relay, 3.2+ for sequential)
- `rg` (ripgrep, for RAG context — optional but recommended)
- `docker` (for lane containers — optional)
- `python3` + `pytest` (for browser-use tests — optional)
