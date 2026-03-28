# Claude Dev Tools — Agent Instructions

Dev tooling suite for AI-powered multi-agent development workflows.
Uses Claude Code CLI (`claude -p`) for agent execution.

## Overview

This repo provides reusable scripts for:

- **relay-race** — Parallel multi-agent task execution with quality gates
- **review-pr** — 5-reviewer parallel PR review (correctness, complexity, test coverage, file org, security)
- **fix-loop** — Automated PR review + fix + re-review loop
- **describe-pr** — Auto-generate PR title, summary, and labels from diff
- **lane** — Docker container management for isolated dev environments
- **pr-watch** — CI check watcher with failure reporting
- **pick-browser-tests** — AI-driven browser test selection based on git diff
- **screenshot** — Playwright page screenshots
- **ask-gemini** — Gemini CLI wrapper for bulk file analysis

## Configuration

Each project using these tools has a `.devtools.yaml` in its root.
See `.devtools.yaml.example` for all available options.

Key config sections: `project`, `static_analysis`, `review`, `relay`, `lane`, `browser_tests`, `hygiene`.

## Agent Definitions

Agent prompts live in `agents/*.md` as markdown files with YAML frontmatter.
Projects override agents by placing files in `.devtools/agents/` with the same name.

## Multi-Model Strategy

| Role                   | Model                            | Script              |
| ---------------------- | -------------------------------- | ------------------- |
| Correctness reviewer   | Sonnet                           | review-pr, fix-loop |
| Complexity reviewer    | Opus                             | review-pr, fix-loop |
| Test coverage reviewer | Sonnet                           | review-pr, fix-loop |
| File org reviewer      | Sonnet                           | review-pr, fix-loop |
| Security reviewer      | Sonnet                           | review-pr, fix-loop |
| Meta-reviewer          | Sonnet                           | fix-loop            |
| Code fixer             | Sonnet                           | fix-loop            |
| Task runner            | Haiku/Sonnet/Opus (per task tag) | relay-race          |
| Static analysis gate   | None (deterministic)             | relay-race          |
| Test reviewer gate     | Sonnet                           | relay-race          |
| Code simplifier gate   | Haiku                            | relay-race          |
| Hygiene gate           | Haiku                            | relay-race          |
| Review gate            | Opus                             | relay-race          |
| Visual critique gate   | Sonnet                           | relay-race          |
| Planning agent         | Opus                             | opus-plan           |

## TASKS.md Format (classic mode)

```markdown
- [ ] **Task AG-1: [sonnet] Short title**
      Description and acceptance criteria.
  - Criterion 1
  - Criterion 2

- [ ] **Task AG-2: [haiku] Depends on AG-1** [needs: AG-1]
      Won't start until AG-1 is done.
```

Tags: `[haiku]`, `[sonnet]`, `[opus]` — determines which model runs the task.
Dependencies: `[needs: TASKID]` or `[needs: ID1, ID2]` at end of title line.

## GitHub Issues Mode

For persistent, cross-session task tracking, use GitHub Issues instead of TASKS.md.

```bash
devtools relay-race --issues --milestone relay-20240115 --parallel 3
devtools relay-race --issues          # auto-generates milestone relay-YYYYMMDD-HHMMSS
```

Issue conventions:

- Labels: `model:sonnet`, `status:pending`, `size:M`, `relay`
- Dependencies in body: `**Depends on:** #174, #175` (or "none")
- Milestone: one per relay run (e.g. `relay-20240115-143022`)

Hydrate tasks.json manually from a milestone:

```bash
bin/hydrate-tasks --milestone relay-20240115 --output .relay-tasks.json
```

Set default mode in `.devtools.yaml`:

```yaml
relay:
  source: issues # or tasks_file (default)
```

## Relay Race Flags

```bash
devtools relay-race                          # sequential, creates PR
devtools relay-race --parallel 3             # up to 3 concurrent agents
devtools relay-race --no-pr                  # commit to current branch
devtools relay-race --dry-run                # show execution plan
devtools relay-race --skip-review            # skip Opus review gate
devtools relay-race --skip-static-analysis   # skip deterministic lint/typecheck gate
devtools relay-race --skip-browser           # skip browser-use gate
devtools relay-race --skip-hygiene           # skip hygiene gate
devtools relay-race --skip-simplify          # skip code simplifier gate
devtools relay-race --skip-security          # skip security reviewer in PR review
devtools relay-race --issues                 # use GitHub Issues mode
devtools relay-race --milestone NAME         # scope issues mode to this milestone
devtools relay-race --tasks-json FILE        # explicit path to tasks.json (default: .relay-tasks.json)
```

## Review-PR Flags

```bash
devtools review-pr 42                # review PR #42
devtools review-pr --incremental 42  # only new commits since last review
devtools review-pr --skip-security 42  # skip security reviewer
devtools review-pr --skip-test-coverage 42  # skip test coverage reviewer
devtools review-pr --approve 42      # auto-approve if clean
```

## Quality Gates (relay-race)

Run automatically after all tasks complete:

1. **Static analysis** (deterministic) — tsc, eslint, prettier on changed files
2. **Code simplifier** (Haiku) — per-task, flags dead code and duplication
3. **Test reviewer** (Sonnet) — per-task, writes missing tests
4. **Hygiene** (Haiku) — checks rules file size, doc clutter, broken refs
5. **Opus review** (Opus) — reviews full diff, fixes violations in-place
6. **Visual critique** (Sonnet vision) — screenshots UI pages, flags regressions

## Duration Tracking

Every LLM invocation logs wall-clock time to `.relay-locks/duration-report.jsonl`.
Summary included in relay PR body.

## Common Mistakes

- Using `### Heading` instead of `- [ ]` checkbox — relay won't detect these
- Missing `- [ ]` at line start (must be exactly `- [ ] ` with space after `]`)
- In parallel mode: agent must NOT modify TASKS.md or commit — relay handles both
- In parallel mode: agent MUST write `.relay-locks/done-TASKID` to signal completion
