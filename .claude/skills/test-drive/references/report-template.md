# Test Drive Report Template

Use this structure for all test-drive reports. Sections with no findings should show "None" rather than being omitted.

```markdown
# Test Drive Report - {YYYY-MM-DD}

## Scope
- Mode: [branch|unstaged]
- Branch: `{branch-name}` vs `main`
- Files changed: N
- Routes affected: [list or "none"]

## Backend Checks (Tidewave MCP)

### Passed

| Check | Description | Result |
|-------|-------------|--------|
| A1 | [what was verified] | PASS |

### Issues Found
- **[critical|warning|info]**: [description]
  - Location: [file:line]
  - Expected: [what should happen]
  - Actual: [what happens]
  - Evidence: [Tidewave output or query result]

## UI Checks (Chrome DevTools MCP)

### Pages Tested

| Check | Description | Result |
|-------|-------------|--------|
| B1 | [route + what was tested] | PASS/FAIL |

### Issues Found
- **[critical|warning|info]**: [description]
  - Steps to reproduce: [steps]
  - Expected: [behavior]
  - Actual: [behavior]

## Edge Cases

| Check | Description | Result |
|-------|-------------|--------|
| C1 | [edge case tested] | PASS/FAIL |

## Auto-Fixes Applied
- [file:line]: [what was fixed and why]
- Or: None

## Issues Filed
- #[number]: [title] (if any issues were created via /create-issue)
- Or: None

## Recommendations
- [actionable items for manual follow-up]
- Or: None
```

## Severity Definitions

| Severity | Meaning | Action |
|----------|---------|--------|
| critical | Broken functionality, data loss risk, crash | Must fix before merge |
| warning | Degraded UX, missing validation, edge case failure | Should fix before merge |
| info | Minor cosmetic issue, improvement opportunity | Can fix later |

## Report Naming

- Default: `.test-drive-reports/test-drive-{YYYY-MM-DD}.md`
- If exists for today: `.test-drive-reports/test-drive-{YYYY-MM-DD}-{HHmm}.md`
- For issue-specific: `.test-drive-reports/test-drive-{YYYY-MM-DD}-{issue-number}.md`
