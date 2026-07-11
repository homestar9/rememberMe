# AGENTS.md

This file provides guidance when working with code in this repository. It is a living document and should be updated by the LLM when it makes notable changes to the codebase, functionality, patterns, or when it identifies important information that should be documented for future maintainers.

## What this is

RememberMe is a Coldbox Module that provides a "remember me" functionality for user authentication. It allows users to stay logged in across sessions by storing a token in a cookie and validating it against a database.

## Architecture

The module is small. Four files carry all of it:

- `ModuleConfig.cfc` — settings (`userServiceClass`, `tokenEncryptKey`, `tokenEncryptAlgorithm`, `validatorHashAlgorithm`, `days`), the custom interception point `onRecall`, `this.dependencies = [ "qb" ]`, and the WireBox mapping for `RememberMeService@rememberMe`.
- `models/RememberMeService.cfc` — the whole implementation. Raw `qb` against a hardcoded `user_remember` table, plus the native `cookie` scope. No ORM, no cbstorages, no cachebox.
- `interfaces/IUserRememberService.cfc` — the one-method contract (`retrieveUserById`) a host app's `userServiceClass` must satisfy.
- `helpers/Mixins.cfm` — the `remember()` application helper.

**The token scheme.** `rememberMe()` generates a `selector` and a `validator` (both UUIDs). The cookie carries `encrypt( selector & "_" & rawValidator )`; the database stores the selector alongside `hash( validator )`. On recall, the cookie's raw validator is hashed and compared to the stored hash. That asymmetry is the point: a stolen database yields hashes an attacker cannot present back. **Do not "simplify" this by storing the same value in both places** — that is precisely the bug that was fixed in 1.2.0, and `test-harness/tests/specs/integration/RecallSpec.cfc` has a spec ("throws InvalidToken for a real selector with a forged validator") that fails loudly if it regresses.

There is **no token rotation**: recall updates only the audit columns (`ipAddress`, `userAgent`, `lastUsedDate`, `modifiedDate`). The selector/validator and `expirationDate` persist for the life of the row.

## Running tests (TestBox)

The suite lives in `test-harness/`, a ColdBox app whose only job is to load the module and run its specs. It talks to a **real SQL Server** database (table `user_remember`), configured via a gitignored `.env` at the repo root (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USER`, `DB_PASSWORD`).

First time:

```
box install                       # qb -> modules/qb
cd test-harness && box install    # coldbox + testbox
```

Then start an engine and hit the runner:

```
box run-script start:lucee5       # or start:lucee6 / start:2023 / start:boxlang
```

| URL | What it runs |
|---|---|
| `http://127.0.0.1:60305/` | Harness home page. Confirms the module registered and `remember()` exists. |
| `.../tests/runner.cfm?directory=tests.specs.unit` | Unit specs. No DB, no qb, no cookies. |
| `.../tests/runner.cfm?directory=tests.specs.integration` | Integration specs. Real DB, real cookies. |
| `.../tests/runner.cfm?directory=tests.specs&recurse=false` | `ModuleSpec` only — the "does it even load" sanity bundle. |
| `.../tests/runner.cfm?bundles=tests.specs.unit.RememberMeServiceSpec` | One bundle, while iterating. |

Add `&reporter=text` for plain-text output. **Run the directories separately** — a bundle that throws at instantiation takes down the whole runner request, so keeping them apart isolates the damage.

Stop the engine (`box run-script stop:lucee5`) before starting another; they all bind port **60305**.

### Engine status (last verified 2026-07-11)

| Engine | ModuleSpec | Unit | Integration |
|---|---|---|---|
| Lucee 5.4.8 | 6/6 | 18/18 | **22/22** |
| Lucee 6.2.7 | 6/6 | 18/18 | **22/22** |
| Adobe 2023 | 6/6 | 18/18 | 18/22 |
| BoxLang 1 | 6/6 | 18/18 | 6/22 |

**Red on Adobe and BoxLang is expected. It is a real module bug, not a harness bug and not a regression.** Both trace to one thing: the cookie write in `rememberMe()` ([RememberMeService.cfc:103-111](models/RememberMeService.cfc#L103-L111)) assigns a **struct of cookie attributes** to the `cookie` scope, which is a Lucee feature.

- **BoxLang** (16 errors): `Can't cast [30] to a DateTime`. BoxLang accepts the struct form but requires `expires` to be a DateTime, not the day-count integer Lucee takes. Every spec that calls `rememberMe()` dies.
- **Adobe 2023** (4 failures): the *write* works, but `forgetMe()`'s `cfcookie( expires="now" )` + `cookie.delete()` does not remove the key from ACF's in-request cookie scope. `cookieExists()` stays true, so `recallMe()` throws `InvalidToken` where it should throw `MissingCookie`.

The portable fix is to rewrite the write as a `cfcookie()` call (the form `forgetMe()` already uses) with a real date for `expires`. That was deliberately **not** done — the decision was to let the suite document the break rather than silently change behaviour. Fix it and all four engines should go green.

## Writing specs

Both base classes extend `coldbox.system.testing.BaseTestCase`. Use its `getInstance()` / `getWireBox()` — do not hardcode component paths, do not `createObject()`.

- **`tests.resources.BaseUnitSpec`** — no DB, no qb, no cookies. `buildService()` returns a service with its private methods exposed (`makePublic`) and its settings pinned via `$property()`. It builds a **fresh instance** per call (`createMock()` on the path taken from the WireBox binder) rather than `getInstance()`, because `RememberMeService@rememberMe` is a **singleton** and several specs need two services with *different* settings to compare (e.g. "cannot be decrypted with a different key"). Off `getInstance()` those would be the same object, `$property()` on the second would mutate the first, and the comparison would prove nothing.
- **`tests.resources.BaseIntegrationSpec`** — real DB, real qb, real cookie scope. `variables.service` is the genuine wired singleton from `getInstance()`. Helpers: `resetState()`, `allTokens()`, `tokenCount()`, `forgeToken( selector, validator )`, `putRememberCookie()`, `recallSpy()`.

Both call `request.coldBoxVirtualApp.restart()` in `beforeAll()` to purge WireBox singletons — and any `$property()` mocks a previous bundle left on them — between bundles.

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

qb's grammar is **pinned** to `SqlServerGrammar@qb` in the harness config rather than left to AutoDiscover — cheap and deterministic.

## Module gotchas worth knowing

- `variables._table = "user_remember"` and the cookie name are **hardcoded** in the service. Configurable table name is on the roadmap.
- `user_remember.modifiedDate` is `NOT NULL` with **no default**, so `rememberMe()`'s INSERT must supply it. It does (this was a bug fixed in 1.2.0 — the INSERT omitted it, which meant the module could not write a row to its own documented schema). Canonical schema: `test-harness/tests/resources/schema.sql`.
- `getCookie()` is not null-safe — it throws if the cookie is absent. Gate on `cookieExists()`.
- `getUserService()` memoises into `variables.userService` on first call.
- The `remember()` helper comes from `this.applicationHelper`. In the harness the module is registered late (`afterAspectsLoad`), after ColdBox's helper-injection pass has already run, so `config/Coldbox.cfc` must re-announce `cbLoadInterceptorHelpers` or `remember()` silently does not exist. This is very likely the same root cause as the README's "Known Issues" note about `remember` being unresolvable on first load.
