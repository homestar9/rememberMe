# Change Log

## 1.4.0

### Added

- **Pluggable token storage.** Persistence is extracted behind a storage-provider seam: the service delegates all reads/writes to the class named by the new `tokenStorageClass` setting (a WireBox DSL, mirroring `userServiceClass`). The default, `QBTokenStorage@rememberMe` (`models/QBTokenStorage.cfc`), is the same qb code as before — public API and out-of-the-box behaviour are unchanged. The contract lives in `interfaces/ITokenStorage.cfc`; providers receive plain values only, and never see a raw validator (all crypto stays in the service).
- New module settings: `tokenStorageClass` (default `"QBTokenStorage@rememberMe"`), `table` (default `"user_remember"` — the previously hardcoded table name), and `datasource` (default `""` = the application default from your `Application.cfc`, passed per-query via qb's `options`).
- New unit bundle `QBTokenStorageSpec.cfc`, new integration bundle `CustomStorageSpec.cfc` (full lifecycle against an in-memory provider, plus datasource-option plumbing), and a harness `StubTokenStorage.cfc` that `implements` the shipped interface to prove it is satisfiable.

## 1.3.0

### Added

- **Automatic purging of stale token rows.** A ColdBox scheduled task (`config/Scheduler.cfc`, registered as `cbScheduler@rememberMe`) runs daily at `purgeTime` and deletes rows whose `expirationDate` passed more than `purgeGraceDays` days ago. Enabled by default; set `autoPurge = false` to disable (the task stays registered but no-ops). Expired rows were already unusable — `recallMe()` rejects them — this is table hygiene.
- New public service method `purgeExpired( numeric graceDays )` returning the number of rows deleted, for manual/host-app-scheduled cleanup.
- New module settings: `autoPurge` (default `true`), `purgeGraceDays` (default `1`), `purgeTime` (default `"04:00"`, server time).
- New index `IX_user_remember_expirationDate` in the canonical schema (`test-harness/tests/resources/schema.sql`), added idempotently for existing databases.
- New integration bundle `PurgeSpec.cfc` plus ModuleSpec assertions for the scheduler, task, and settings defaults.

### Fixed

- **Test harness:** both base spec classes no longer restart the ColdBox virtual app in `beforeAll()`. All bundles in a runner request share one request, and ColdBox 7's WireBox memoises transient dependencies there (`request.cbTransientDICache`) — so restarting mid-request left later bundles' rebuilt transients wired to the previous boot's shut-down services. The visible symptom was `onRecall` announcements that no registered interceptor ever heard, in multi-bundle runs only. Latent until 1.3.0 added a second integration bundle. See AGENTS.md trap 6.

## 1.2.1

### Fixed

**The suite is now green on all four engines (Lucee 5, Lucee 6, Adobe 2023, BoxLang 1).** The 1.2.0 "Known issues" entry below is resolved:

- The cookie write in `rememberMe()` is now a portable `cfcookie()` call with a DateTime `expires` instead of a Lucee-only attribute-struct assignment to the `cookie` scope. This fixes every `rememberMe()` call erroring on BoxLang (`Can't cast [30] to a DateTime`). `path="/"` is set on all engines except Adobe, whose `cfcookie` refuses `path` without `domain` — ACF defaults its cookies to `Path=/` anyway.
- `cookieExists()` now treats an empty cookie value as absent. Adobe CF never removes an expired/deleted cookie's key from the in-request `cookie` scope — it leaves it behind with an empty value — so after `forgetMe()`, `recallMe()` on ACF threw `InvalidToken` where it should throw `MissingCookie`. An empty token is unusable regardless of engine, so "empty means missing" is the honest semantic everywhere.
- `forgetMe()` uses `structDelete()` instead of the member-function form `cookie.delete()`.

## 1.2.0

### Security

**Fixed: the validator half of the selector/validator scheme was dead code.** Two bugs cancelled each other out, so nothing looked broken:

- `parseToken()` re-hashed an already-hashed value, so the parsed validator could never equal the stored one.
- `isMatch()` was inverted — `compare()` returns 0 when strings are equal, so the function returned `true` when they *differed*.

The net effect was that the validator comparison in `recallMe()` never rejected anything. **Any decryptable cookie whose selector matched a database row would authenticate, regardless of its validator.** The encryption key was the only real secret.

`rememberMe()` now stores the *hashed* validator in the database and puts the *raw* validator in the cookie — the canonical scheme, where a stolen database yields hashes an attacker cannot present back. `isMatch()` compares correctly.

**Breaking:** existing remember-me cookies will no longer validate. They are rejected as `InvalidToken`, which the documented consumer pattern already catches and handles by calling `forgetMe()`. Users will be logged out once on deploy.

### Fixed

- `rememberMe()` did not populate `modifiedDate` on INSERT, but the documented schema has that column as `NOT NULL` with no default — so the module could not write a row to its own schema. It now sets `modifiedDate` at creation.

### Added

- A TestBox `test-harness/` with unit and integration suites (46 specs). See `AGENTS.md` for how to run them, and for the per-engine status matrix.
- `qb` is now declared as a dependency in `box.json`. `ModuleConfig.cfc` has always declared `this.dependencies = [ "qb" ]`, but `box install rememberMe` never actually installed it.

### Known issues (fixed in 1.2.1)

The cookie write in `rememberMe()` assigns a struct of cookie attributes to the `cookie` scope, which is Lucee-specific. The suite is green on Lucee 5 and 6, and fails on Adobe 2023 (4 specs) and BoxLang (16 specs) because of it. See `AGENTS.md` for detail.

## 1.1.1

Version bump.

## 1.1.0

Added custom interception point, `onRecall`, to interceptor settings in the module configuration. This interceptor fires when the `remember().recall()` method is called, allowing for custom logic to be executed during the recall process (like logging).

## 1.0.0

Initial release.
Changed the method name for retrieving users to match the interface used by cbauth. We will now use `retrieveUserById()` instead of `getUserById()`.