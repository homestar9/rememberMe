# AGENTS.md

This file provides guidance when working with code in this repository. It is a living document and should be updated by the LLM when it makes notable changes to the codebase, functionality, patterns, or when it identifies important information that should be documented for future maintainers.

## What this is

RememberMe is a Coldbox Module that provides a "remember me" functionality for user authentication. It allows users to stay logged in across sessions by storing a token in a cookie and validating it against a database.

## Architecture

- `ModuleConfig.cfc` — settings (`userServiceClass`, `tokenEncryptKey`, `tokenEncryptAlgorithm`, `validatorHashAlgorithm`, `days`, `autoPurge`, `purgeGraceDays`, `purgeTime`, `tokenStorageClass`, `table`, `datasource`), the custom interception point `onRecall`, and the WireBox mappings for `RememberMeService@rememberMe`, `SQLTokenStorage@rememberMe`, `MemoryTokenStorage@rememberMe` and `QBTokenStorage@rememberMe`. All NoScope (`binder.map().to()` with no annotation is a transient, not a singleton) **except MemoryTokenStorage, which is `asSingleton`** — see below. **`this.dependencies` is deliberately absent as of 2.0.0; do not add one.**
- `models/RememberMeService.cfc` — the domain logic: cookie handling (native `cookie` scope), all crypto, the recall/remember/forget lifecycle. Since 1.4.0 it holds **no persistence** — every read/write goes through the storage provider resolved from `tokenStorageClass` (lazy, memoised per instance in `getTokenStorage()`, mirroring `getUserService()`).
- `models/SQLTokenStorage.cfc` — **the default storage provider since 2.0.0.** Plain `queryExecute` against the `table` setting on the `datasource` setting ("" = the application default, passed per-query via the options struct). Zero dependencies. See the SQL portability rules below before touching the statements.
- `models/MemoryTokenStorage.cfc` — an in-memory provider (a struct keyed by selector, every method under a named `lock`). For development, tests, and as the shortest complete implementation to copy when writing a provider. **Mapped `asSingleton` and it must stay that way** — a transient in-memory store would be rebuilt empty on every injection and could never recall anything. ModuleSpec asserts the singleton behaviourally.
- `models/QBTokenStorage.cfc` — an **opt-in** provider: raw `qb`, behaviourally identical to SQLTokenStorage. The module does not install qb; the host app must `box install qb`. Its qb reference is lazy (`getQB()`, try/catch, throws `MissingDependency` with the fix in the message) rather than a build-time `provider:` injection, so the component still constructs — and its mapping still resolves — on an app with no qb.
- `config/Scheduler.cfc` — the module scheduler (auto-registered by ColdBox as `cbScheduler@rememberMe`). One task, `rememberMe-purge-expired-tokens`, runs `purgeExpired()` daily at `purgeTime`; `.when()` gates it on `autoPurge` at runtime, so disabling leaves the task registered but inert. See the scheduler gotchas below before touching it.
- `interfaces/IUserRememberService.cfc` — the one-method contract (`retrieveUserById`) a host app's `userServiceClass` must satisfy.
- `interfaces/ITokenStorage.cfc` — the seven-method contract (`create`, `getBySelector`, `updateUsage`, `deleteBySelector`, `deleteByUserId`, `deleteAll`, `deleteExpiredBefore`) a custom `tokenStorageClass` must satisfy. Documentation-style, never enforced with `implements=` in the module itself; the harness's `StubTokenStorage` does implement it, proving it satisfiable.
- `helpers/Mixins.cfm` — the `remember()` application helper.

**Why there is no `this.dependencies` (2.0.0).** ColdBox does not isolate module dependencies. `ModuleService.registerModule()` scans a registered module's own `modules/` and `modules_app/` folders as "inception paths" and registers what it finds as real, application-wide modules. So up to 1.4.0, `this.dependencies = [ "qb" ]` plus `box.json`'s `installPaths: { qb: "modules/qb/" }` meant installing rememberMe forced a qb version into the host app's registry, where it could collide with the app's own. That is the entire reason 2.0.0 exists. **Do not reintroduce a module dependency** — write it in plain CFML, or make it an opt-in provider like QBTokenStorage.

**The storage seam's two invariants** (both spec-guarded; do not trade them away):

- **All crypto stays in the service.** A storage provider only ever sees the selector and the ALREADY-HASHED validator, never the raw validator — so a custom provider cannot recreate the pre-1.2.0 bug.
- **Plain values only across the interface** (strings, numerics, native dates). The service computes everything, dates included; storage stamps nothing and holds no policy (grace-period math included — `deleteExpiredBefore` receives a cutoff *date*). `cfsqltype` annotations are each SQL provider's internal business and must not leak into the contract.

**SQL portability rules in `SQLTokenStorage.cfc`** (all four engines green; do not "clean these up"):

- **Named `:param` bindings**, not positional `?` — the 8-column INSERT would misalign silently when a column is added.
- **Short `cfsqltype` spellings** (`varchar`, `timestamp`, `integer`), matching QBTokenStorage. Verified on Lucee 5, Lucee 6, Adobe 2023 and BoxLang 1.
- **No `TOP`/`LIMIT` in `getBySelector`.** qb's `.first()` emitted a SQL-Server-only `TOP (1)`. The selector is a `createUuid()` on an indexed column, so it is a single-row seek anyway — use `returntype: "array"` and take `[ 1 ]`. `TOP` is SQL Server only, `LIMIT` is not SQL Server, and ANSI `FETCH FIRST` needs an `ORDER BY` on SQL Server.
- **`deleteExpiredBefore` uses the `result` option and reads `recordCount`**, with a `structKeyExists` guard. This is the same mechanism qb used internally. Do **not** replace it with `select count(*)` then `delete`: two statements can disagree if another request inserts between them, and the number is only used for logging.
- **`getTable()`'s allow-list regex is deliberately backslash-free** (`^[A-Za-z0-9_.]+$`). Inside a character class, a backslash is a literal in Adobe's POSIX engine and an escape in the Java engine Lucee and BoxLang use, so `[\.\[\]]` means different things per engine. Square-bracket quoting is not supported and never was — qb would have double-wrapped `[user_remember]` too.
- **`getQueryOptions()` returns a fresh struct literal every call**, because `getBySelector` and `deleteExpiredBefore` both add a key to what they get back. A spec guards this.
- `getTable()`/`getQueryOptions()` are read **per call, not snapshotted in `onDIComplete`** — the unit specs build these components with `createMock()` + `$property()`, which skips the WireBox lifecycle entirely, so a snapshot would silently never happen there.

**The token scheme.** `rememberMe()` generates a `selector` and a `validator` (both UUIDs). The cookie carries `encrypt( selector & "_" & rawValidator )`; the database stores the selector alongside `hash( validator )`. On recall, the cookie's raw validator is hashed and compared to the stored hash. That asymmetry is the point: a stolen database yields hashes an attacker cannot present back. **Do not "simplify" this by storing the same value in both places** — that is precisely the bug that was fixed in 1.2.0, and `test-harness/tests/specs/integration/RecallSpec.cfc` has a spec ("throws InvalidToken for a real selector with a forged validator") that fails loudly if it regresses.

There is **no token rotation**: recall updates only the audit columns (`ipAddress`, `userAgent`, `lastUsedDate`, `modifiedDate`). The selector/validator and `expirationDate` persist for the life of the row. Since 1.3.0 that life has an end: `purgeExpired()` deletes rows whose `expirationDate` passed more than `purgeGraceDays` days ago, run daily by the module scheduler (expired rows were already unusable — `recallMe()` rejects them — so purging is hygiene, never a behaviour change).

**Scheduler gotchas** (all verified against the vendored ColdBox 7 source in `test-harness/coldbox/`):

- `config/Scheduler.cfc` must be a **plain component** with `configure()` — ColdBox applies virtual inheritance from `ColdBoxScheduler` at load (`SchedulerService.loadScheduler`). Do not add `extends`. Inside `configure()` you get `task()`, `getInstance()`, `log`, and the `moduleSettings` mixin.
- The task uses `everyDayAt( purgeTime )` deliberately: `every( n, "days" )` fires its first run **immediately at scheduler startup** — an immediate-fire purge would DELETE mid-suite whenever the harness boots. `everyDayAt` computes a delay to the next occurrence and never fires at startup.
- `.when()` is evaluated at **runtime** per tick, not at scheduling — an `autoPurge=false` task stays registered (ModuleSpec asserts on this) but no-ops. `task.run( force = true )` bypasses both the schedule and `.when()`; `PurgeSpec` uses it to drive the task end-to-end.
- Late module registration is safe: LoaderService announces `afterAspectsLoad` **before** `startupSchedulers()`, so the harness's `registerAndActivateModule` in `afterAspectsLoad` still gets the scheduler registered and started.

## Running tests (TestBox)

The suite lives in `test-harness/`, a ColdBox app whose only job is to load the module and run its specs. It talks to a **real SQL Server** database (table `user_remember`), configured via a gitignored `.env` at the repo root (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USER`, `DB_PASSWORD`).

First time:

```
box install                       # nothing to install — the module has no dependencies
cd test-harness && box install    # coldbox + testbox + qb
```

**qb is the HARNESS's dependency, not the module's.** It installs to `test-harness/modules/qb` (declared in `test-harness/box.json`) and exists only so `QBTokenStorageSpec` and the QB half of `CustomStorageSpec` have something to run against. Both `test-harness/Application.cfc` and `test-harness/tests/Application.cfc` hand-map `/qb` and `/cbpaginator` from there — keep those declared explicitly, because ColdBox creates them mid-request and a mapping created mid-request is not resolvable for component lookups in that same request, so the first cold request would die. **Never let qb reappear under `<repo>/modules/`**: ColdBox would then register it twice, once by the harness's convention scan and once as an inception child of rememberMe.

Then start an engine and hit the runner:

```
box run-script start:lucee5       # or start:lucee6 / start:2023 / start:boxlang
```

| URL | What it runs |
|---|---|
| `http://127.0.0.1:60305/` | Harness home page. Confirms the module registered and `remember()` exists. |
| `.../tests/runner.cfm?directory=tests.specs.unit` | Unit specs. No DB, no cookies. |
| `.../tests/runner.cfm?directory=tests.specs.integration` | Integration specs. Real DB, real cookies. |
| `.../tests/runner.cfm?directory=tests.specs&recurse=false` | `ModuleSpec` only — the "does it even load" sanity bundle. |
| `.../tests/runner.cfm?bundles=tests.specs.unit.RememberMeServiceSpec` | One bundle, while iterating. |

Add `&reporter=text` for plain-text output. **Run the directories separately** — a bundle that throws at instantiation takes down the whole runner request, so keeping them apart isolates the damage.

Stop the engine (`box run-script stop:lucee5`) before starting another; they all bind port **60305**.

### Engine status (last verified 2026-08-05)

| Engine | ModuleSpec | Unit | Integration |
|---|---|---|---|
| Lucee 5.4.8 | 14/14 | 55/55 | **33/33** |
| Lucee 6.2.7 | 14/14 | 55/55 | **33/33** |
| Adobe 2023 | 14/14 | 55/55 | **33/33** |
| BoxLang 1.15 | 14/14 | 55/55 | **33/33** |

Also verified once, by hand, with `test-harness/modules/qb` moved aside entirely: ModuleSpec 14/14, unit 55/55, integration 32/33 — the single failure being the one spec that deliberately uses qb, which fails with the intended `MissingDependency` message. That is the only way to prove the module runs without qb, because the harness itself installs qb. Worth repeating if you touch `getQB()` or the `onLoad()` mappings.

All four engines are green as of 1.3.0 (counts grew in 2.0.0: `SQLTokenStorageSpec` (10 unit) and `MemoryTokenStorageSpec` (13 unit) were added, ModuleSpec gained the no-dependencies / three-provider / singleton assertions, and CustomStorageSpec gained the second datasource spec and the table-validation spec; in 1.4.0: the storage abstraction added `QBTokenStorageSpec` (6 unit), `CustomStorageSpec` (4 integration), storage-delegation unit specs, and ModuleSpec storage assertions; in 1.3.0: `PurgeSpec` added 5 integration specs, ModuleSpec added scheduler/purge-settings assertions). All four engines were first green in 1.2.1. Before that, Adobe failed 4 integration specs and BoxLang errored on 16, because the cookie write in `rememberMe()` assigned a **struct of cookie attributes** to the `cookie` scope — a Lucee-only idiom (BoxLang additionally rejected the integer day-count `expires`). The service's cookie handling is now deliberately shaped around three engine quirks; keep them in mind before "cleaning it up":

- **The write is a `cfcookie()` call with a DateTime `expires`, built via `attributeCollection`.** The struct is needed because ACF's `cfcookie` refuses `path` without `domain` — at *compile* time, so a literal `path=` attribute in the source breaks ACF even inside dead code. The service adds `path="/"` on non-Adobe engines only; ACF defaults its cookies to `Path=/` anyway, so behaviour matches.
- **ACF never removes a cookie key from the in-request `cookie` scope.** Every deletion mechanism — `cfcookie( expires="now" )`, `structDelete()`, `cookie.delete()`, plain reassignment — just queues an expiring response cookie, and that queued cookie shows straight back through the scope as a key with an **empty value** (`structDelete` even re-adds it under an UPPERCASE name). There is no way to make `structKeyExists( cookie, name )` go false on ACF once the name has been touched.
- Therefore **`cookieExists()` treats an empty value as absent**. That is the entire ACF fix: after `forgetMe()`, the key survives in ACF's scope but its value is `""`, which `cookieExists()` (and hence `recallMe()`, correctly throwing `MissingCookie`) reads as "no cookie". Lucee and BoxLang genuinely remove the key, so the `len()` check is a no-op there.

Browser-side deletion is done by `forgetMe()`'s `cfcookie( expires="now", preserveCase=true )` — `preserveCase` matters because browsers match cookie names case-sensitively, and ACF's `structDelete` emits its junk expiry header uppercased.

## Writing specs

Both base classes extend `coldbox.system.testing.BaseTestCase`. Use its `getInstance()` / `getWireBox()` — do not hardcode component paths, do not `createObject()`.

- **`tests.resources.BaseUnitSpec`** — no DB, no cookies. `buildService()` returns a service with its private methods exposed (`makePublic`) and its settings pinned via `$property()`. It builds a **fresh instance** per call (`createMock()` on the path taken from the WireBox binder) rather than `getInstance()`: several specs need two services with *different* settings to compare (e.g. "cannot be decrypted with a different key"), and a mock built this way is independent of WireBox entirely. (Note: despite older comments, the mapping is **not** a singleton — `binder.map().to()` with no annotation is NoScope, so every `getInstance()` builds a new transient.)
- **`tests.resources.BaseIntegrationSpec`** — real DB, real cookie scope. `variables.service` is the genuine wired service from `getInstance()`. Helpers: `resetState()`, `allTokens()`, `tokenCount()`, `forgeToken( selector, validator )`, `putRememberCookie()`, `recallSpy()`. `variables.TABLE` is re-derived from the module's `table` setting in `beforeAll()` — don't hardcode the table name in specs.
- Storage-seam specs, and which one to reach for:
  - `unit/SQLTokenStorageSpec` and `unit/QBTokenStorageSpec` — settings derivation only, no DB. Both build the component with `createMock()` on the path from the WireBox binder.
  - `unit/MemoryTokenStorageSpec` — the whole seven-method contract, driven directly. It is the only provider whose contract can be fully covered without a database, and it is deliberately written against the contract rather than the struct inside, so anyone building a provider can lift the bundle and repoint `buildStorage()`. It uses `createMock()` rather than `getInstance()` on purpose: the real mapping is `asSingleton`, so `getInstance()` would leak state between specs.
  - `integration/RecallSpec` and `integration/PurgeSpec` — the real end-to-end coverage for `SQLTokenStorage`, since the wired service resolves it by default. They read rows back with raw `queryExecute` rather than through the provider, so they would catch a provider that wrote the wrong thing.
  - `integration/CustomStorageSpec` — the seam itself, driven through `test-harness/models/StubTokenStorage.cfc`. That stub stays even though the module now ships `MemoryTokenStorage`, because it lives OUTSIDE the module and is the only proof a host app's own class can satisfy the contract.
- When a spec needs a custom provider, override `tokenStorageClass` on a `prepareMock()`ed service instance **inside the spec** — never in `test-harness/config/Coldbox.cfc`, which would silently swap the storage under every other integration bundle. For the same reason, the harness config deliberately does not override `tokenStorageClass`, `table`, `datasource` or the purge settings: ModuleSpec asserts those as the module's own defaults.

Neither restarts the virtual app — see trap 6, which is the single most expensive thing to rediscover in this harness. Per-spec isolation comes from `resetState()`, whose first act is `setup()` (BaseTestCase's per-spec request reset — without it ColdBox treats every spec in a bundle as one request).

### Traps that will cost you an afternoon

1. **TestBox does not call a component-level `beforeEach()` on a BDD bundle.** Only the closures registered *inside* a `describe()` fire. Declaring `function beforeEach()` on a base class looks right and silently does nothing. Every BDD bundle must register them itself:
   ```cfc
   describe( "...", function() {
       beforeEach( function( currentSpec ) { resetState(); } );
       afterEach(  function( currentSpec ) { resetState(); } );
   ```
   (`beforeAll()` / `afterAll()` *are* bundle lifecycle methods and do fire.)
2. **Every spec in a `?directory=` run shares one HTTP request, therefore one `cookie` scope.** A cookie set by `rememberMe()` in one spec is visible to the next spec's `cookieExists()`. That is what `resetState()` is for. Symptom if you forget: specs pass alone and fail in a suite.
3. **`this.name` must not contain spaces.** The service derives its cookie name as `"rememberMe-" & application.applicationName`, and HTTP cookie names must be RFC 6265 tokens. Hence `rememberMe-harness` / `rememberMe-tests`.
4. **An interceptor listening for `onRecall` must be registered AFTER the module.** ColdBox binds an interceptor's methods to interception points at *registration* time, and `onRecall` is a custom point that only exists once rememberMe has registered. Declare it in the `interceptors` config array and its `onRecall()` is silently never bound — the event fires and nothing hears it. See `afterAspectsLoad()` in `test-harness/config/Coldbox.cfc`, which registers `RecallSpy` explicitly after the module.
5. **Coverage must stay off.** TestBox coverage instrumentation compiles every CFML file in its path, including ColdBox's CacheBox report skin, which uses the chart tag — Lucee 6 dropped that tag from core, so coverage-on means *every* Lucee 6 run dies before a single spec executes. `tests/runner.cfm` defaults `coverage` to false. Same reason `debugMode` is false in the harness config.
6. **Never call `request.coldBoxVirtualApp.restart()` in a spec's `beforeAll()`.** It reads as good hygiene and it silently breaks every bundle after the first. All bundles in a `?directory=` run share ONE request, and ColdBox 7's WireBox memoises each transient's resolved dependencies for the request in `request.cbTransientDICache`. Restart mid-request and that cache still holds the **previous, shut-down boot's** `interceptorService` / `wirebox` / `cachebox`, which WireBox then injects into every transient it rebuilds. Two symptoms, both of which cost an afternoon: the service announces `onRecall` into a dead InterceptorService (so `RecallSpy` hears nothing and the spec fails "Expected [1] but received [0]"), and `ColdBoxScheduledTask` gets an empty CacheFactory (so `task.run()` dies with "Cache template is not registered" in its post-run cleanup). Both appear **only from the second bundle onward** — every bundle passes when run alone, which is what makes it so disorienting. Only build-time property injection reads the cache; a direct `getInstance( dsl = "coldbox:interceptorService" )` returns the live one, so the two disagree and the wiring looks fine everywhere you'd think to look. There is nothing to purge by restarting anyway: the service mapping is NoScope (a transient), and `BaseUnitSpec` mocks a `createMock()` instance that WireBox never manages. The per-request VirtualApp from `tests/Application.cfc` is all the app-level isolation the suite needs.

### Engine portability gotchas hit while building this harness

- **Adobe cannot chain a method off an array literal.** `[ "a", "b" ].each( ... )` is "Invalid CFML construct" on ACF, fine on Lucee. Assign to a variable first.
- **Adobe requires `property` declarations to precede any `this.*` assignment** in a component. (Spec bundles aren't autowired by WireBox anyway, so `property inject="wirebox"` is a no-op — use `getWireBox()`.)
- **Lucee 6 resolves `include` against the webroot and won't walk up out of a mapped directory.** `include "../config/Datasource.cfm"` fails in a pseudo-constructor — i.e. before any error handler exists — so you get a bare 500 with an empty body and nothing in the logs. Use webroot-absolute: `/config/Datasource.cfm`.
- **Lucee 6's parser reacts to a tag name in angle brackets even inside a `//` comment.** Writing the chart tag's name in a comment reproduces the very error you were documenting. Don't.
- **Build mapping paths with `getCanonicalPath()`, not string concat.** The ColdBox paths already end in a separator, so naive concatenation yields `...\rememberMe\modules/qb`. Lucee tolerates mixed separators; Adobe does not, and you get "Could not find the ColdFusion component qb.models.Query.QueryBuilder".
- **Never delete `.engine/<name>` while its JVM is alive.** It corrupts the engine's context deployment, and the resulting errors (Lucee 6 losing its own `writeDump.cfm` and `error.cfm`) look like application bugs. Stop the server first.

## The harness's datasource

Defined in `test-harness/config/Datasource.cfm`, included from the pseudo-constructor of **both** `test-harness/Application.cfc` and `test-harness/tests/Application.cfc`.

It is deliberately **not** in `.cfconfig.json`: the MSSQL JDBC driver class differs per engine (Adobe ships DataDirect's `macromedia.jdbc.MacromediaDriver`; Lucee ships Microsoft's `com.microsoft.sqlserver.jdbc.SQLServerDriver`; BoxLang wants its own `bx-mssql` module), and a single `.cfconfig.json` is shared by all four `server-*.json` files. Defining it on the application lets one file serve every engine. `.cfconfig.json` keeps engine settings only.

Engine prerequisites, already wired into the `server-*.json` files:
- **Adobe 2023** — `cfpm install sqlserver` (in `onServerInstall`).
- **BoxLang** — `bx-mssql` (in `onServerInitialInstall`).

qb's grammar is **pinned** to `SqlServerGrammar@qb` in the harness config rather than left to AutoDiscover — cheap and deterministic. That `moduleSettings.qb` block configures the harness's own qb, not the module's; the module has had no qb since 2.0.0.

## Module gotchas worth knowing

- The table name and datasource are configurable since 1.4.0 (`table`, `datasource` settings, consumed by `SQLTokenStorage` and `QBTokenStorage`; `MemoryTokenStorage` ignores both). The cookie name is still **hardcoded** (`"rememberMe-" & application.applicationName`).
- **QBTokenStorage only:** qb's `delete()` takes `( id, idColumnName, options )` — the options struct is the THIRD positional parameter, so it must be passed as a named argument (`.delete( options = getQueryOptions() )`). Passed positionally it becomes an id filter and the datasource option is silently dropped. The other terminal methods (`insert`, `update`, `first`, `get`) take options second and QBTokenStorage names it everywhere anyway.
- `user_remember.modifiedDate` is `NOT NULL` with **no default**, so the INSERT (in whichever SQL provider is configured; values supplied by `rememberMe()`) must supply it. Both do (this was a bug fixed in 1.2.0 — the INSERT omitted it, which meant the module could not write a row to its own documented schema). `lastUsedDate` is the opposite case: the schema's only nullable column, deliberately absent from the INSERT column list, NULL until the first recall. Canonical schema: `test-harness/tests/resources/schema.sql`.
- `getCookie()` is not null-safe — it throws if the cookie is absent. Gate on `cookieExists()`.
- `getUserService()` and `getTokenStorage()` memoise into `variables.userService` / `variables.tokenStorage` on first call (per service instance — the mapping is NoScope).
- The `remember()` helper comes from `this.applicationHelper`. In the harness the module is registered late (`afterAspectsLoad`), after ColdBox's helper-injection pass has already run, so `config/Coldbox.cfc` must re-announce `cbLoadInterceptorHelpers` or `remember()` silently does not exist. This is very likely the same root cause as the README's "Known Issues" note about `remember` being unresolvable on first load.
