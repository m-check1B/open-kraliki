# [Module Name] — Product Audit

**Date:** YYYY-MM-DD
**Status:** Draft / In Progress / Complete

---

## 1. Mission Snapshot

<!-- What this module SHOULD do, synthesized from the product spec. 3-5 sentences. -->

## 2. Current Reality

<!-- What actually works today. Include a route/API surface table. -->

| Route / Endpoint | Status | Notes |
|-----------------|--------|-------|
| `/module` | ✅ / ⚠️ / ❌ | |
| `/module/api/v1/...` | ✅ / ⚠️ / ❌ | |

## 3. Feature Completion Map

| # | Feature | Route | UI | Backend | Status | Notes |
|---|---------|-------|----|---------|--------|-------|
| F1 | Feature name | ✅/❌ | ✅/❌ | ✅/❌ | DONE/PARTIAL/MISSING | |
| F2 | Feature name | ✅/❌ | ✅/❌ | ✅/❌ | DONE/PARTIAL/MISSING | |

## 4. User Journey Gaps

<!-- Walk each core use case. See METHODOLOGY.md §4 for format. -->

```
UC1: "As a user, I want to..."
  Entry: /module → ?
  Step 1: ... → ?
  VERDICT: ? | Priority: P?
```

## 5. Priority Actions

### P0 — Beta Blockers
<!-- - [ ] `[Module] P0: Title` (S/M/L) — reason this is P0 -->

### P1 — Beta Quality
<!-- - [ ] `[Module] P1: Title` (S/M/L) -->

### P2 — Post-Beta
<!-- - [ ] `[Module] P2: Title` (S/M/L) -->

## 6. Dependencies

### Upstream (this module depends on)
<!-- - Module X: for authentication -->

### Downstream (depends on this module)
<!-- - Module Y: needs our API for data -->

## 7. Linear Issue Breakdown

<!-- Ready-to-import issues. Copy to Linear using linear-tool.py or manually. -->

| # | Title | Priority | Labels | Effort |
|---|-------|----------|--------|--------|
| 1 | `[Module] P0: ...` | P0 | backend, route | S |
| 2 | `[Module] P1: ...` | P1 | frontend, ui | M |

## 8. Open Product Questions

<!-- Decisions needed before engineering can proceed. -->

1. **Q:** ?
   **Impact:** Blocks F? implementation
   **Options:** A / B / C

## 9. Competitive Context

<!-- What competitors do well that we should match or beat. What's our moat. -->

### Moats (protect these)
<!-- - Unique feature X -->

### Gaps (close these)
<!-- - Competitor Y has feature Z that we lack -->
