# AntigravityUsageWatcher — Implementation Plan

Goal: a macOS menu bar app that shows Antigravity quota (per model + prompt credits), with the same “/tmp/antigravity-usage” UX/features, but without relying on the Antigravity extension host. We will:

- Perform a first-run **Google OAuth login** in the user’s browser.
- Store tokens in **Keychain**.
- Spawn Antigravity’s bundled `language_server_macos_arm` in the background.
- Call **Connect RPC over HTTPS + HTTP/2** to `GetUserStatus` and render quotas.

---

## 0) Feature Parity (from `/tmp/antigravity-usage`)

From `/tmp/antigravity-usage` (extension) we port these user-facing features:

1) **Status bar indicator**
- Minimal display: primary model short-name + remaining percent (e.g. `Sonnet 75%`).
- Color/background changes for low/critical thresholds.
- Tooltip/menu includes all models with remaining% and reset time.

2) **Active model detection (heuristic)**
- Derivative-based “active” model: highest burn rate in history, fallback to last-active, fallback to lowest remaining.

3) **Predictive analytics (insights)**
- Burn rate (%/hour)
- Predicted time-to-empty (ETE)
- Session usage
- 24h usage buckets (history chart)

4) **Prompt credits**
- Display available/monthly + percent remaining.

5) **Dashboard UI**
- A “Quota dashboard” window (our equivalent to the extension’s webview dashboard).
- Ability to toggle “Show insights” vs minimal view.

6) **Pinning**
- User can pin a model; pinned model becomes primary in the status bar.

7) **Refresh / reconnect controls**
- Manual refresh
- “Restart connection” (our equivalent of re-detecting port) → restart spawned LS.

8) **Cache management** (maps to `.gemini/antigravity/*`)
- Show cache sizes: brain, conversations, code context.
- “Clean cache” (brain + conversations)
- “Manage brain tasks” (list tasks with size/date, delete one)

---

## 1) Key Decisions (confirmed)

- OAuth client: reuse `opencode-antigravity-auth` client id + secret.
- Redirect: local HTTP callback, **random port each login**.
- Accounts: single account in v1, but storage modeled for future multi-account.
- Token storage: Keychain.
- LS lifecycle: keep spawned in background; restart on failure.
- Dependency: require `/Applications/Antigravity.app` installed; reuse its LS + cert.

---

## 2) Architecture Overview

### Components

1) **OAuthController**
- Generates PKCE verifier/challenge.
- Builds Google auth URL (`https://accounts.google.com/o/oauth2/v2/auth`).
- Runs local callback server on `127.0.0.1:<random>/oauth-callback`.
- Exchanges auth code at `https://oauth2.googleapis.com/token`.

2) **TokenStore (Keychain)**
- Persists refresh token + metadata (token type, expiry, email optional).
- Provides “load auth state”, “save auth state”, “delete auth state”.

3) **TokenRefresher**
- When access token is expired/near-expiry, refresh using `grant_type=refresh_token`.
- Returns `{ accessToken, refreshToken?, expiry, tokenType }`.

4) **LanguageServerSupervisor**
- Spawns `language_server_macos_arm` with fixed port and csrf token.
- Feeds stdin protobuf `exa.codeium_common_pb.Metadata` (with `apiKey = accessToken`).
- Keeps process alive; restarts on crash.

5) **LanguageServerClient**
- Connect unary calls over HTTPS + HTTP/2 to `https://127.0.0.1:<port>`.
- Uses pinned CA cert:
  - `/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/dist/languageServer/cert.pem`
- Required header: `x-codeium-csrf-token: <csrf>`.
- Calls:
  - `SaveOAuthTokenInfo`
  - `GetUserStatus`

6) **QuotaParser + Models**
- Parse `GetUserStatus` protobuf response into:
  - `PromptCredits` (available/monthly)
  - `[ModelQuota]` (label, modelId, remaining%, reset time)

7) **InsightsService** (ported from `/tmp/antigravity-usage/src/insights.ts`)
- Stores 24h history snapshots.
- Computes burn rate, active model, ETE, session usage, usage buckets.

8) **UI Layer**
- Menu bar item: primary display + menu.
- Dashboard window (SwiftUI): model list, credits, sparklines, insights toggle, usage buckets, cache management.

---

## 3) OAuth Flow (macOS)

### 3.1 Authorization URL (PKCE)
- Generate `code_verifier` and `code_challenge` (S256).
- Use scopes (same as opencode):
  - `https://www.googleapis.com/auth/cloud-platform`
  - `https://www.googleapis.com/auth/userinfo.email`
  - `https://www.googleapis.com/auth/userinfo.profile`
  - `https://www.googleapis.com/auth/cclog`
  - `https://www.googleapis.com/auth/experimentsandconfigs`
- Build auth URL with:
  - `client_id`
  - `redirect_uri=http://127.0.0.1:<randomPort>/oauth-callback`
  - `response_type=code`
  - `code_challenge`, `code_challenge_method=S256`
  - `access_type=offline`, `prompt=consent`
  - `state` = base64url JSON payload containing at least `{ verifier, nonce }`

### 3.2 Callback server
- Start a local HTTP server bound to `127.0.0.1` on a random port.
- Accept only `GET /oauth-callback`.
- Extract `code` and `state`, validate state/nonce, then respond with a “Success, you can close this window” HTML page.

Implementation options (no external deps):
- `Network.framework` (`NWListener`) + minimal HTTP parsing.

### 3.3 Code exchange
- POST `application/x-www-form-urlencoded` to `https://oauth2.googleapis.com/token`:
  - `grant_type=authorization_code`
  - `code`
  - `code_verifier`
  - `redirect_uri`
  - `client_id`
  - `client_secret`
- Store refresh token in Keychain.

### 3.4 Refresh
- POST to `https://oauth2.googleapis.com/token`:
  - `grant_type=refresh_token`
  - `refresh_token`
  - `client_id`
  - `client_secret`
- Update Keychain if refresh token is rotated.

---

## 4) Language Server Integration

### 4.1 Spawn strategy
- Binary:
  - `/Applications/Antigravity.app/Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm`
- Start it once, keep alive.
- Use fixed port selection in our app (e.g. choose an available port at launch) and a generated CSRF token.

### 4.2 Required stdin handshake
- On startup, write protobuf bytes for `exa.codeium_common_pb.Metadata` to stdin and close stdin.
- Must include at least:
  - `ide_name`, `extension_name`, `extension_path`, `device_fingerprint`, `locale`, `os`
  - `api_key = access_token`

### 4.3 RPC calls (Connect, HTTP/2)
- Base URL: `https://127.0.0.1:<port>`
- Unary endpoint format:
  - `POST /exa.language_server_pb.LanguageServerService/<Method>`
- Headers:
  - `Content-Type: application/proto`
  - `Accept: application/proto`
  - `Connect-Protocol-Version: 1`
  - `x-codeium-csrf-token: <csrf>`
- TLS trust: pinned CA certificate at `.../languageServer/cert.pem`.

### 4.4 Auth sequence per refresh cycle
1) Ensure access token is valid (refresh if needed).
2) Spawn/ensure LS is running.
3) Call `SaveOAuthTokenInfo` (protobuf body).
4) Call `GetUserStatus({ metadata })`.

---

## 5) Quota + Insights Model

### 5.1 Parsed data
- `ModelQuota`
  - `label`, `modelId`
  - `remainingPercent`, `usedPercent`, `isExhausted`
  - `resetTime`, `timeUntilReset`
- `PromptCredits`
  - `available`, `monthly`, `usedPercent`, `remainingPercent`

### 5.2 Insights (ported)
- Persist snapshots for 24h (rolling window).
- Burn rate (%/hour) over history window.
- Predicted exhaustion label (e.g. `~2h 15m`), “Safe for now”, “Exhausted”.
- Active model detection (burn-rate leader with thresholds).
- Usage buckets (24h, 60m bins) for bar chart.

Persistence location (non-secret):
- `~/Library/Application Support/com.google.antigravity.usagewatcher/history.json` (or similar)

---

## 6) UI Design (Status Bar + Dashboard)

### 6.1 Menu bar
Signed out:
- `Sign in with Google…`
- `Quit`

Signed in:
- Primary line: `<PrimaryModelShort> <Remaining>%` (status bar title)
- Menu:
  - `Open Dashboard`
  - `Refresh Now`
  - `Pin Model…` / `Unpin Model…`
  - Separator
  - Model list (read-only summary lines): `› Model: 75% · 3h 10m`
  - Credits line (if available): `Credits: 9,000 / 10,000`
  - Separator
  - `Manage Cache…` (opens dashboard to cache section)
  - `Clean Cache…`
  - Separator
  - `Sign out`
  - `Quit`

### 6.2 Dashboard window (SwiftUI)
- Model cards/rows, each shows:
  - Label, remaining%, reset time
  - Sparkline of last N points
  - Optional insights panel: burn rate, ETE, session usage
- Prompt credits summary
- Usage history chart (24h buckets)
- Cache section:
  - sizes + counts
  - list brain tasks with delete action
  - clean all action

---

## 7) Error Handling + Privacy

- Never log tokens or full OAuth responses.
- Keychain-only for secrets.
- If LS dies: restart and retry a limited number of times.
- If auth fails (invalid_grant, revoked): show signed-out state and prompt re-login.
- If Antigravity.app missing/outdated:
  - Status bar shows “Antigravity not installed” and offers “Open Antigravity download page” (optional).

---

## 8) Status (What’s Done / What’s Next)

### Done (MVP wired end-to-end)

- **OAuth login in-app**: PKCE + browser-based sign-in + loopback callback on `127.0.0.1:<random>/oauth-callback`.
- **Keychain storage**: refresh token + minimal metadata stored under Keychain service `com.google.antigravity.usagewatcher`.
- **Language server supervisor**:
  - Spawns `/Applications/Antigravity.app/.../language_server_macos_arm`.
  - Writes `exa.codeium_common_pb.Metadata` protobuf bytes to stdin and closes stdin.
- **LS RPC client**:
  - Uses pinned CA from `/Applications/Antigravity.app/.../languageServer/cert.pem`.
  - Calls `SaveOAuthTokenInfo` (best-effort) and `GetUserStatus`.
- **Quota parsing**: extracts prompt credits + per-model quotas from `GetUserStatus` response (aligned with `/tmp/antigravity-usage/src/quotaService.ts`).
- **Menu bar UI**:
  - Signed out: “Sign in with Google…”.
  - Signed in: primary model display (`ShortName XX%`), refresh, model list, pin/unpin, sign out.

### Deviations / Known Gaps

- **Connect RPC encoding**: the long-term target is Connect *binary unary* (`Content-Type: application/proto`) over **HTTP/2**.
  - Current Swift client uses JSON payloads (matching `/tmp/antigravity-usage`) because it’s the fastest path to a working MVP.
  - If Antigravity changes/locks down JSON, we must switch to protobuf bodies.
- **No dashboard yet**: “Open Dashboard…” is stubbed.
- **No insights yet**: history + burn rate + ETE + usage buckets not implemented.
- **No cache management yet**: `.gemini/antigravity/*` sizes/clean/tasks not implemented.

### Next (in priority order)

1) **Dashboard window (SwiftUI)**
- Add a SwiftUI window that shows model rows/cards + prompt credits.
- Add a “Show insights” toggle placeholder (even before full insights is ready).

2) **Polling + reliability**
- Add a refresh timer (e.g. every 60–120s) + manual refresh.
- Improve error messages: missing Antigravity.app, token revoked/expired, LS died.

3) **InsightsService (port)**
- Persist 24h snapshot history in app support.
- Implement burn rate, predicted exhaustion (ETE), active model heuristic, and usage buckets (port from `/tmp/antigravity-usage/src/insights.ts`).

4) **Cache tools (port)**
- Implement cache size scanning + “clean cache” + brain task list/delete, using the same directory structure as `/tmp/antigravity-usage/src/cacheService.ts`.

5) **Protocol hardening**
- Switch LS RPC to Connect binary unary + HTTP/2 (to match the bundled extension exactly).
  - If needed, add a protobuf codegen dependency (e.g. SwiftProtobuf) *only* for the specific request messages we must send.

---

## Notes for implementation

- The probe script `scripts/antigravity_ls_probe.py` demonstrates the LS-side requirements and validates that Opencode-derived OAuth tokens are accepted.
- The Swift MVP intentionally prioritizes a working user flow; protocol parity (binary protobuf over HTTP/2) is a follow-up hardening step.
