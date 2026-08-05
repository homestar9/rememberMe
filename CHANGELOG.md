# Change Log

## 2.0.0

### Changed

- **The module no longer depends on `qb`.** `ModuleConfig.cfc` dropped `this.dependencies = [ "qb" ]` and `box.json` dropped the dependency and its install path, so `box install rememberMe` now installs exactly one package and adds nothing to the host app's module registry. The reason is that ColdBox does not isolate module dependencies: it registers a module's own `modules/` folder as real, application-wide modules, so the qb that shipped inside rememberMe was forced onto the host app and could collide with the version that app had chosen for itself.
- **New default storage provider: `SQLTokenStorage@rememberMe`** (`models/SQLTokenStorage.cfc`). Plain `queryExecute` against the same `table` and `datasource` settings, with the same columns and the same behaviour as the qb provider it replaces. The SQL is deliberately dialect-neutral ANSI — no `TOP`/`LIMIT`, no bracket quoting, no vendor functions.

  **Breaking:** the `tokenStorageClass` default changed from `"QBTokenStorage@rememberMe"` to `"SQLTokenStorage@rememberMe"`. If you never set that setting there is nothing to do — the table, the columns, the cookies and the token scheme are all unchanged, and no user gets logged out. If you did set it to `QBTokenStorage@rememberMe`, that provider still ships and still works, but you must now run `box install qb` in your own app. If your app used qb only because rememberMe installed it, add it to your own `box.json` before it disappears on your next `box install`.

- **`QBTokenStorage@rememberMe` is now opt-in and requires the host app to install qb.** The file stays in the module and stays mapped. Its qb injection moved from a build-time `property name="qb" inject="provider:QueryBuilder@qb"` to a lazy `getQB()`, so the component builds fine on an app with no qb and only fails if something actually uses it — with a `MissingDependency` error naming both fixes (`box install qb`, or switch to `SQLTokenStorage`).

### Added

- **New in-memory storage provider: `MemoryTokenStorage@rememberMe`** (`models/MemoryTokenStorage.cfc`), mapped `asSingleton` because a transient in-memory store would be rebuilt empty on every injection. It is for development, for tests, and for trying the module out before creating the token table — tokens are lost on application restart and are not shared across cluster nodes, so it is documented as not for production. It is also the shortest complete implementation of `interfaces/ITokenStorage.cfc`, which makes it the file to copy when writing a custom provider.
- A "Writing your own token storage" section in the README with a complete copy-paste skeleton of all seven methods, plus a provider comparison table and an "Upgrading from 1.x" section.
- `SQLTokenStorage` validates the `table` setting against an allow-list and throws `InvalidConfiguration` otherwise. A table name is an identifier and cannot be a bind parameter, so it is interpolated into the SQL; qb used to pass it through its grammar's `wrapValue()` and raw SQL does not, so this restores that layer.
- New unit bundles `SQLTokenStorageSpec.cfc` (10 specs) and `MemoryTokenStorageSpec.cfc` (13 specs, the full contract driven directly). `ModuleSpec` gained assertions that the module declares no dependencies, that all three providers map, and that `MemoryTokenStorage` really is a singleton. `CustomStorageSpec` now exercises the datasource option on both SQL-backed providers.
- qb moved to `test-harness/box.json` as a harness dependency, installed into `test-harness/modules/qb`, so the QBTokenStorage specs keep running against the real thing.

### Verified

All four engines green — Lucee 5.4.8, Lucee 6.2.7, Adobe 2023 and BoxLang 1.15 — at 14 ModuleSpec, 55 unit and 33 integration specs. `RecallSpec` and `PurgeSpec` drive the wired service, so they exercise every `SQLTokenStorage` statement against a real SQL Server and assert on the rows directly.

Separately verified by hand with qb removed from the harness entirely: the module boots, all three mappings resolve, and the whole suite passes except the one spec that deliberately uses qb — which fails with the intended `MissingDependency` message.

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