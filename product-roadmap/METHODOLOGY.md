# Product Completion Roadmap — Methodology

A systematic framework for auditing product modules from spec to shipping state.

---

## 1. Three-Layer Reality Model

A feature is **Done** only when all three layers are green. Any single red layer means the feature is not shippable.

| Layer | Question | How to verify |
|-------|----------|---------------|
| **Route** | Does the URL/page/endpoint exist? | Check for route file at the expected path |
| **UI** | Does the page show real, dynamic data (not placeholder/hardcoded)? | Load the page — check network tab for API calls |
| **Backend** | Is the API wired to a real data source? | Trace the route handler → service layer → database/external service |

### Layer Status Notation

```
✅ / ✅ / ✅  = Route exists, UI shows real data, backend wired     → DONE
✅ / ⚠️ / ✅  = Route exists, UI partially connected, backend works  → PARTIAL
✅ / ❌ / ❌  = Route exists but page is a stub                      → MISSING (scaffolded)
❌ / ❌ / ❌  = No route at all                                      → MISSING (not started)
```

---

## 2. Feature Status Taxonomy

| Status | Definition | Criteria |
|--------|-----------|----------|
| **DONE** | Feature works end-to-end | All 3 layers green; acceptance criteria met |
| **PARTIAL** | Feature partially works | 1-2 layers green; core path works but edge cases missing |
| **MISSING** | Feature not operational | Route may exist but UI is stub or backend not wired |
| **DEFERRED** | Intentionally postponed | Product decision to defer — documented with rationale |
| **BLOCKED** | Cannot proceed | Blocked by dependency, open question, or external service |

---

## 3. Priority Classification

| Priority | Label | Definition | Gate |
|----------|-------|-----------|------|
| **P0** | Beta blocker | Must work for beta to ship | Ship blocker |
| **P1** | Beta quality | Should work for quality beta | Quality bar |
| **P2** | Post-beta | Nice to have, can ship without | Backlog |

### Priority Assignment Rules

1. **P0 if**: Feature is a core use case AND is the primary user journey for the module
2. **P0 if**: Feature is a cross-module dependency that other P0s depend on
3. **P1 if**: Feature is important but not the primary journey, or it's a quality/polish item
4. **P2 if**: Feature is an open question or competitive gap
5. **P0 override**: Any security vulnerability or data-loss risk is automatically P0

---

## 4. User Journey Audit

For each module, walk every core use case:

1. **Start at the entry point** — the module's root route
2. **Follow the happy path** — click through the intended flow
3. **Log break points** — where the journey hits a stub, error, or dead end
4. **Rate the journey**: Complete ✅ | Breaks at step N ⚠️ | Cannot start ❌

### Journey Log Format

```
UC1: "As a user, I want to..."
  Entry: /module → ✅ loads
  Step 1: Open panel → ✅ UI renders
  Step 2: Select option → ⚠️ dropdown present but no data loaded
  Step 3: Submit → ❌ 500 error
  VERDICT: Breaks at step 2-3 | Priority: P0
```

---

## 5. Linear Issue Format Standard

### Issue Title Convention

```
[Module] P{0|1|2}: Verb noun phrase
```

Examples:
- `[Auth] P0: Wire login endpoint to database`
- `[Dashboard] P1: Connect analytics chart to real data`
- `[Workflow] P2: Add conditional branching to builder`

### Required Labels

| Label Category | Values |
|---------------|--------|
| **Priority** | `P0-beta-blocker`, `P1-beta-quality`, `P2-post-beta` |
| **Module** | Your module names (e.g., `auth`, `dashboard`, `api`) |
| **Work Type** | `backend`, `frontend`, `full-stack`, `infra`, `design`, `product-decision` |
| **Layer** | `route`, `ui`, `backend`, `cross-cutting` |

### Issue Body Template

```markdown
## Context
[1-2 sentences: what should exist and what actually exists today]

## Acceptance Criteria
- [ ] [Criterion from spec, verbatim or minimally adapted]
- [ ] [Additional criterion if needed]

## Spec Reference
- Spec: `docs/product/<module>.md` §{section}
- Feature: F{n} — {feature name}

## Dependencies
- Blocked by: [issue links or "none"]
- Blocks: [issue links or "none"]

## Effort Estimate
S / M / L
```

### Effort Sizing

| Size | Definition | Rough scope |
|------|-----------|-------------|
| **S** | < 1 day | Single file change, wiring existing pieces, config |
| **M** | 1-3 days | New component or API endpoint, moderate integration |
| **L** | 3-5+ days | New subsystem, multi-file feature, external integration |

---

## 6. Per-Module Document Template (9 Sections)

Each module document follows this structure:

| # | Section | Content |
|---|---------|---------|
| 1 | **Mission Snapshot** | What the module SHOULD do (from spec) |
| 2 | **Current Reality** | What actually works today + route/API surface table |
| 3 | **Feature Completion Map** | Feature-by-feature: Status × 3 layers |
| 4 | **User Journey Gaps** | Walk each core use case, log where journey breaks |
| 5 | **Priority Actions** | P0/P1/P2 ordered list with effort estimates |
| 6 | **Dependencies** | Upstream/downstream module dependencies |
| 7 | **Linear Issue Breakdown** | Ready-to-import issues with title, labels, acceptance criteria |
| 8 | **Open Product Questions** | Decisions needed before engineering can proceed |
| 9 | **Competitive Context** | Moats to protect + gaps to close |

---

## 7. Execution Order

Work proceeds in waves, ordered by dependency depth:

| Wave | Modules | Rationale |
|------|---------|-----------|
| **1 — Foundation** | Auth, Admin | Everything depends on authentication and governance |
| **2 — Core Loop** | Primary user-facing modules | Daily-use surfaces |
| **3 — Data + Coordination** | Data pipeline and automation | Integration fabric |
| **4 — Advanced** | Learning, analytics, reporting | Depends on earlier waves |
| **5 — Specialist** | Independent tools, security | Most independent; security cross-cuts |

Customize the wave assignments to match your project's dependency graph.

---

## 8. Verification Checklist

After all module documents are written, verify:

- [ ] Every feature from every spec appears in at least one Feature Completion Map
- [ ] Every P0/P1 action has a matching Linear Issue Breakdown entry
- [ ] Every Linear issue has acceptance criteria + spec reference
- [ ] Dependencies are consistent (if A lists B, B acknowledges A)
- [ ] No orphan issues — every issue traces back to a spec section
- [ ] Priority assignments are consistent with the rules in §3

---

## 9. Source File Index

| File | Purpose |
|------|---------|
| Product specs | Feature definitions + acceptance criteria |
| Gap analysis | Current implementation vs spec |
| Module documents | Per-module audit (using this methodology) |
| Master checklist | Cross-module issue tracker |

Adapt the source file locations to your project structure.
