---
name: Browser Test Guide
description: Project-specific guide for writing browser-use tests — override this per project
model: none
role: reference
variables:
  - PROJECT_NAME
  - BROWSER_TESTS_DIR
---

# Browser-Use Testing Guide for {{PROJECT_NAME}}

This is the default guide. Override it at `.devtools/agents/browser-test-guide.md`
with your project-specific patterns.

## Test Structure

Tests live in `{{BROWSER_TESTS_DIR}}/test_*.py` and use pytest + browser-use.

## Writing a New Test

1. Create `{{BROWSER_TESTS_DIR}}/test_<feature>.py`
2. Import shared fixtures from `conftest.py` (BASE_URL, test credentials, etc.)
3. Use `browser_use.Agent` with a clear step-by-step task string
4. Assert on `final_result()` text using POSITIVE indicators
5. Add error handling and cleanup in `finally` block

## What Belongs in Browser-Use vs Unit Tests

**Browser-use** (real browser required):
- Login/auth flows
- File uploads with real binary data
- Drag-drop, hover states, complex DOM interactions
- Visual verification (element visibility, layout)
- Multi-step user journeys

**Unit/integration tests** (mock dependencies):
- API route handlers
- Data processing logic
- Database queries (mock the client)

## Test Manifest

Add new tests to the manifest at `{{BROWSER_TESTS_DIR}}/test-manifest.json`:
```json
{
  "tests": {
    "my_feature": {
      "name": "My Feature Test",
      "description": "Tests the my_feature flow",
      "triggers": ["src/app/my-feature/**"],
      "cost": "$0.10",
      "duration": "2min"
    }
  }
}
```

Override this file with your project's specific patterns, fixtures, and conventions.
