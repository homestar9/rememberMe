# Change Log

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

### Known issues

The cookie write in `rememberMe()` assigns a struct of cookie attributes to the `cookie` scope, which is Lucee-specific. The suite is green on Lucee 5 and 6, and fails on Adobe 2023 (4 specs) and BoxLang (16 specs) because of it. See `AGENTS.md` for detail.

## 1.1.1

Version bump.

## 1.1.0

Added custom interception point, `onRecall`, to interceptor settings in the module configuration. This interceptor fires when the `remember().recall()` method is called, allowing for custom logic to be executed during the recall process (like logging).

## 1.0.0

Initial release.
Changed the method name for retrieving users to match the interface used by cbauth. We will now use `retrieveUserById()` instead of `getUserById()`.