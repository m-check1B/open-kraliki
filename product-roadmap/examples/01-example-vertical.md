# Auth Module — Product Audit (Example)

**Date:** 2026-01-15
**Status:** Complete

> This is a worked example showing what a filled-in module audit looks like. Copy `VERTICAL-TEMPLATE.md` and fill in your own modules.

---

## 1. Mission Snapshot

The Auth module handles user authentication and session management. Users should be able to sign up, log in (email + password or OAuth), reset passwords, and manage their sessions. Admin users can view and revoke active sessions. All API endpoints behind `/api/` require a valid session token.

## 2. Current Reality

Basic email/password login works. OAuth (Google) is scaffolded but not connected. Password reset sends emails but the reset page has a broken form. Session management UI exists but shows hardcoded data.

| Route / Endpoint | Status | Notes |
|-----------------|--------|-------|
| `/login` | ✅ | Email/password works |
| `/signup` | ✅ | Creates user in DB |
| `/forgot-password` | ⚠️ | Email sends, reset page broken |
| `/api/auth/session` | ✅ | Returns current session |
| `/api/auth/oauth/google` | ❌ | Route exists, not wired to Google |
| `/admin/sessions` | ⚠️ | UI exists, shows hardcoded data |

## 3. Feature Completion Map

| # | Feature | Route | UI | Backend | Status | Notes |
|---|---------|-------|----|---------|--------|-------|
| F1 | Email/password login | ✅ | ✅ | ✅ | DONE | |
| F2 | User signup | ✅ | ✅ | ✅ | DONE | |
| F3 | Password reset | ✅ | ❌ | ✅ | PARTIAL | Reset form broken |
| F4 | Google OAuth | ✅ | ❌ | ❌ | MISSING | Scaffolded only |
| F5 | Session management | ✅ | ⚠️ | ❌ | PARTIAL | UI hardcoded |
| F6 | Admin session viewer | ✅ | ⚠️ | ❌ | PARTIAL | Shows fake data |

## 4. User Journey Gaps

```
UC1: "As a user, I want to log in with email and password"
  Entry: /login → ✅ loads
  Step 1: Enter credentials → ✅ form works
  Step 2: Submit → ✅ redirects to dashboard
  VERDICT: Complete ✅ | Priority: n/a (done)

UC2: "As a user, I want to reset my password"
  Entry: /forgot-password → ✅ loads
  Step 1: Enter email → ✅ sends reset email
  Step 2: Click link in email → ✅ opens reset page
  Step 3: Enter new password → ❌ form submit returns 422
  VERDICT: Breaks at step 3 | Priority: P0

UC3: "As a user, I want to log in with Google"
  Entry: /login → ✅ loads
  Step 1: Click "Sign in with Google" → ❌ 404 from OAuth callback
  VERDICT: Breaks at step 1 | Priority: P1
```

## 5. Priority Actions

### P0 — Beta Blockers
- [ ] `[Auth] P0: Fix password reset form submission` (S) — core user journey broken
- [ ] `[Auth] P0: Wire session management to real session store` (M) — admin needs this

### P1 — Beta Quality
- [ ] `[Auth] P1: Connect Google OAuth to credentials` (M) — scaffolded, needs wiring
- [ ] `[Auth] P1: Add session revocation in admin panel` (S) — UI exists, need API call

### P2 — Post-Beta
- [ ] `[Auth] P2: Add "remember me" checkbox to login` (S)
- [ ] `[Auth] P2: Add login attempt rate limiting` (M)

## 6. Dependencies

### Upstream (Auth depends on)
- **Database**: PostgreSQL for user records and sessions

### Downstream (depends on Auth)
- **Dashboard**: Requires valid session for data access
- **Admin**: Requires admin role check from Auth
- **API**: All endpoints use Auth middleware

## 7. Linear Issue Breakdown

| # | Title | Priority | Labels | Effort |
|---|-------|----------|--------|--------|
| 1 | `[Auth] P0: Fix password reset form — 422 on submit` | P0 | frontend, ui | S |
| 2 | `[Auth] P0: Wire session management to real session store` | P0 | backend | M |
| 3 | `[Auth] P1: Connect Google OAuth callback to credential exchange` | P1 | full-stack | M |
| 4 | `[Auth] P1: Add session revocation API + wire admin UI` | P1 | full-stack | S |
| 5 | `[Auth] P2: Add "remember me" to login form` | P2 | frontend | S |
| 6 | `[Auth] P2: Add rate limiting to login endpoint` | P2 | backend | M |

## 8. Open Product Questions

1. **Q:** Should we support additional OAuth providers (GitHub, Apple)?
   **Impact:** Blocks F4 scope definition
   **Options:** Google only for beta / Add GitHub / Add all three

2. **Q:** What's the session timeout policy?
   **Impact:** Affects F5 implementation
   **Options:** 24h hard timeout / 7d with refresh / Configurable per user

## 9. Competitive Context

### Moats (protect these)
- Unified auth across all modules (single sign-on within the app)
- Session management visible to admins (most competitors hide this)

### Gaps (close these)
- Competitor X has passwordless login (magic links) — consider for v2
- Competitor Y has 2FA — should be P1 for production, can defer for beta
