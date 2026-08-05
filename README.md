# RememberMe

![RememberMe icon](https://github.com/homestar9/rememberMe/blob/master/rememberMe-logo.avif?raw=true)

RememberMe lets a ColdBox app keep a user signed in after the user's session ends.

The module creates a long-lived cookie and stores a matching token on the server. On a later visit, your app can use that token to find the user and start a new login session.

RememberMe does not check passwords or log users in by itself. Your app still needs an authentication system such as cbAuth, cbSecurity, or your own login code.

## Requirements

- ColdBox 7 or newer
- Lucee 5 or newer, Adobe ColdFusion 2023 or newer, or BoxLang 1 or newer
- A user service that can find a user by numeric ID
- A database table for production use

RememberMe has no required package dependencies. The default storage provider uses `queryExecute()` directly.

## Install the module

Run this command from your ColdBox app:

```bash
box install rememberMe
```

Then complete the setup below.

## 1. Create the token table

The default storage provider saves tokens in a table named `user_remember`.

The following SQL creates that table in Microsoft SQL Server:

```sql
CREATE TABLE user_remember (
    id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    createdDate     DATETIME2     NOT NULL,
    modifiedDate    DATETIME2     NOT NULL,
    userId          INT           NOT NULL,
    selector        VARCHAR(35)   NOT NULL,
    hashedValidator VARCHAR(32)   NOT NULL,
    ipAddress       VARCHAR(45)   NOT NULL,
    userAgent       VARCHAR(255)  NOT NULL,
    expirationDate  DATETIME2     NOT NULL,
    lastUsedDate    DATETIME2         NULL
);

CREATE INDEX IX_user_remember_selector
    ON user_remember (selector);

CREATE INDEX IX_user_remember_userId
    ON user_remember (userId);

CREATE INDEX IX_user_remember_expirationDate
    ON user_remember (expirationDate);
```

The repository also includes an [idempotent SQL Server schema](test-harness/tests/resources/schema.sql). You can run that file more than once without recreating the table.

The storage queries use standard SQL. You can use another database engine, but you may need to change the data types and identity column syntax in the setup script.

## 2. Add a user lookup method

RememberMe needs a service that can load one user from a numeric ID. The service must have this method:

```cfc
function retrieveUserById( required id ) {
    // Return your app's user object for arguments.id.
}
```

Your service can implement `rememberMe.interfaces.IUserRememberService`, but the module does not require the `implements` attribute. The method name and argument are the important parts.

Here is a small example:

```cfc
component singleton {

    function retrieveUserById( required id ) {
        return entityLoadByPK( "User", arguments.id );
    }

}
```

Use the lookup code that fits your app. The method may return an ORM entity, a CFC, or another user object that your authentication system accepts.

## 3. Configure RememberMe

Add a `rememberMe` block to `moduleSettings` in `config/Coldbox.cfc`. Keep any other module settings that are already in the struct.

```cfc
moduleSettings = {
    rememberMe = {
        userServiceClass = "UserService",
        tokenEncryptKey = "replace-this-with-your-generated-key",
        days = 30,
        autoPurge = true,
        purgeGraceDays = 1,
        purgeTime = "04:00",
        tokenStorageClass = "SQLTokenStorage@rememberMe",
        table = "user_remember",
        datasource = ""
    }
};
```

`userServiceClass` is the name that WireBox uses to find the service from the previous step. Replace `UserService` with the mapping or component path used by your app.

`tokenEncryptKey` protects the value in the browser cookie. Generate the key once with this CFML code:

```cfc
generateSecretKey( "AES", 256 )
```

Save the generated value in your app's secret storage. Do not generate a new key each time the app starts. A new key makes every existing RememberMe cookie invalid.

The default `datasource` value is an empty string. An empty value tells `queryExecute()` to use the default datasource from your application's `Application.cfc`.

## 4. Remember the user after login

Call `rememberMe()` after your app accepts the user's login. Only call it when the user selects your “Remember me” checkbox.

```cfc
// Your app has already checked the password and loaded the user.
auth().login( user );

if ( event.getValue( "rememberMe", false ) ) {
    remember().rememberMe( user.getId() );
}
```

The `auth()` calls in this guide are cbAuth examples. Replace those calls if your app uses another authentication system.

Calling `rememberMe()` does three things:

1. It removes the current browser's old RememberMe token, if one exists.
2. It stores a new token through the configured storage provider.
3. It sends an encrypted, HTTP-only cookie to the browser.

The cookie lasts for the number of days in the `days` setting.

## 5. Recall the user on later requests

Try to recall a user only when the user is not already logged in. A ColdBox `preProcess()` interceptor is a good place for this check because it runs early on each request.

```cfc
function preProcess( event, interceptData, buffer, rc, prc ) {
    if ( auth().isLoggedIn() || !remember().cookieExists() ) {
        return;
    }

    try {
        var user = remember().recallMe();

        // Change this check if your user object uses another way to report a match.
        if ( user.isLoaded() ) {
            auth().login( user );
        } else {
            remember().forgetMe();
        }
    } catch ( InvalidToken exception ) {
        // The cookie is damaged, expired, forged, or no longer has a matching row.
        remember().forgetMe();
    }
}
```

`recallMe()` returns the value from your user service's `retrieveUserById()` method. RememberMe cannot tell whether that value represents a real user. Your app must check the returned value before starting a login session.

The service throws `InvalidToken` when the cookie cannot be trusted. The example clears the bad cookie so the app does not retry it on every request.

`recallMe()` can also throw `MissingCookie` if no usable cookie exists. Calling `cookieExists()` first normally prevents that error.

## 6. Clear the token during logout

Call `forgetMe()` when the user logs out:

```cfc
remember().forgetMe();
auth().logout();
```

`forgetMe()` deletes the token for the current browser and expires the browser cookie. It is safe to call when no RememberMe cookie exists.

## Using the service without the helper

The `remember()` application helper is convenient in handlers and interceptors. You can also inject the service directly:

```cfc
property name="rememberMeService" inject="RememberMeService@rememberMe";
```

Then call the same methods on `rememberMeService`:

```cfc
rememberMeService.rememberMe( user.getId() );
```

## Common service methods

Most apps only need `rememberMe()`, `cookieExists()`, `recallMe()`, and `forgetMe()`.

| Method | What it does |
| --- | --- |
| `rememberMe(userId)` | Creates a token and sends the browser cookie. The user ID must be numeric. |
| `cookieExists()` | Returns `true` when the current request has a non-empty RememberMe cookie. |
| `recallMe()` | Validates the cookie, updates token usage data, and returns the user from your user service. |
| `forgetMe()` | Deletes the current browser's token and expires its cookie. |
| `deleteByUserId(userId)` | Deletes every stored token for one user. This prevents future recall on all devices. |
| `deleteAll()` | Deletes every stored token. This prevents future recall for all users. |
| `purgeExpired(graceDays)` | Deletes old, expired tokens. When `graceDays` is omitted, the method uses `purgeGraceDays`. |
| `getCookie()` | Returns the encrypted cookie value. Call `cookieExists()` first because `getCookie()` throws when the cookie is missing. |
| `isValidToken(token)` | Checks the cookie format. This method does not check storage or confirm that the token is active. |

Deleting stored tokens does not remove cookies from other browsers. Those cookies will fail validation on their next request, and your recall code should clear them with `forgetMe()`.

Deleting stored tokens also does not end sessions that are already active. Your authentication system must end those sessions if you need to log users out immediately.

## Settings reference

| Setting | Default | Meaning |
| --- | --- | --- |
| `userServiceClass` | `""` | WireBox mapping for the service that has `retrieveUserById()`. You must set this value. |
| `tokenEncryptKey` | `""` | Secret key used to encrypt the cookie. You must set this value. |
| `tokenEncryptAlgorithm` | `"aes"` | Algorithm used to encrypt and decrypt the cookie. |
| `validatorHashAlgorithm` | `"MD5"` | Algorithm used to hash the token validator before storage. |
| `days` | `30` | Number of days before the cookie and stored token expire. |
| `autoPurge` | `true` | Enables the daily task that deletes old token rows. |
| `purgeGraceDays` | `1` | Number of days to keep a token row after the token expires. |
| `purgeTime` | `"04:00"` | Time for the daily purge task, in 24-hour server time. |
| `tokenStorageClass` | `"SQLTokenStorage@rememberMe"` | WireBox mapping for the token storage provider. |
| `table` | `"user_remember"` | Table used by the SQL and qb storage providers. |
| `datasource` | `""` | Datasource used by the SQL and qb providers. An empty value uses the app's default datasource. |

Changing the encryption key, encryption algorithm, or hash algorithm makes existing cookies invalid. Users with those cookies will need to log in again.

The example schema uses `VARCHAR(32)` for `hashedValidator` because the default MD5 hash has 32 characters. Widen that column before you select a hash algorithm with a longer result.

The default SQL provider allows letters, numbers, underscores, and periods in `table`. A schema-qualified name such as `dbo.user_remember` is valid. Quoted names such as `[user_remember]` are not supported.

## How tokens are protected

RememberMe creates two random values for each token: a selector and a validator.

- The encrypted browser cookie contains the selector and the original validator.
- Server storage contains the selector and a hash of the validator.
- Recall succeeds only when the selector finds a stored token and both validator hashes match.

The original validator is never sent to the storage provider. This design means that a copied token table does not contain the value that a browser must present.

The cookie uses `HttpOnly` and `SameSite=Lax`. The module also sets the cookie's `Secure` flag when the current request uses HTTPS.

RememberMe does not rotate a token after recall. A token keeps the same selector, validator, and expiration date until it expires or is deleted.

## Automatic cleanup of expired tokens

An expired token cannot recall a user. The database row still exists until a cleanup removes it.

RememberMe registers a ColdBox scheduled task named `rememberMe-purge-expired-tokens`. The task runs once each day at `purgeTime`. It deletes rows that have been expired for more than `purgeGraceDays`.

For example, the default grace period keeps an expired row for one extra day. Set `purgeGraceDays = 0` to delete rows during the first purge after they expire.

Set `autoPurge = false` to disable automatic deletion. The task remains registered, but the task does no work.

You can also run cleanup yourself:

```cfc
var rememberMeService = getInstance( "RememberMeService@rememberMe" );

// Use the configured purgeGraceDays value.
var deletedCount = rememberMeService.purgeExpired();

// Delete every token that has already expired.
var deletedNowCount = rememberMeService.purgeExpired( 0 );
```

`purgeExpired()` returns the number of deleted rows. A custom storage provider may return `0` when its backend cannot report a count.

In a cluster, the scheduled task runs on every server. Two servers can safely try to delete the same expired rows. A row that one server already deleted gives the other server nothing to delete.

## Token storage options

`tokenStorageClass` selects where RememberMe stores tokens. The value must be a class that WireBox can resolve.

| Provider | Storage location | Extra setup | Recommended use |
| --- | --- | --- | --- |
| `SQLTokenStorage@rememberMe` | A database through `queryExecute()` | Create the token table | Production and most apps |
| `MemoryTokenStorage@rememberMe` | A struct in the app's memory | None | Local development and tests |
| `QBTokenStorage@rememberMe` | A database through qb | Install qb and create the token table | Apps that choose to use qb |

### SQLTokenStorage

`SQLTokenStorage@rememberMe` is the default. It uses the `table` and `datasource` settings. It does not require qb or another package.

### MemoryTokenStorage

To use memory storage, change one setting:

```cfc
tokenStorageClass = "MemoryTokenStorage@rememberMe"
```

Memory storage is useful when you want to try the module before creating a database table.

Do not use memory storage in production. Every application restart deletes all tokens. Each server in a cluster also gets a separate token store. A cookie created on one server will not work on another server.

### QBTokenStorage

RememberMe includes a storage provider for [qb](https://qb.ortusbooks.com/), but RememberMe does not install qb.

Install qb in your app:

```bash
box install qb
```

Then change the provider:

```cfc
tokenStorageClass = "QBTokenStorage@rememberMe"
```

The qb provider uses the same `table` and `datasource` settings as the default provider. If qb is missing, the first storage operation throws a `MissingDependency` error with setup instructions.

## Writing a custom storage provider

You can store tokens in an ORM, Redis, an API, or another backend. Set `tokenStorageClass` to the WireBox mapping for your class:

```cfc
tokenStorageClass = "TokenStorage"
```

The class must provide these seven methods. The full contract is in [`interfaces/ITokenStorage.cfc`](interfaces/ITokenStorage.cfc).

| Method | Required behavior |
| --- | --- |
| `create(token)` | Store `userId`, `selector`, `hashedValidator`, `ipAddress`, `userAgent`, `createdDate`, `modifiedDate`, and `expirationDate`. |
| `getBySelector(selector)` | Return a token struct with at least `userId`, `selector`, `hashedValidator`, and `expirationDate`. Return an empty struct when no token exists. |
| `updateUsage(selector, audit)` | Update `ipAddress`, `userAgent`, `lastUsedDate`, and `modifiedDate`. Do not change the token or its expiration date. |
| `deleteBySelector(selector)` | Delete one token. Do nothing when the token does not exist. |
| `deleteByUserId(userId)` | Delete every token for one user. |
| `deleteAll()` | Delete every token. |
| `deleteExpiredBefore(cutoffDate)` | Delete tokens with an expiration date before the cutoff. Return the number deleted, or `0` if the backend cannot report a count. |

The service passes plain strings, numbers, and date objects to storage. The service also calculates all dates before it calls storage. Your provider should store the supplied values without replacing them.

Storage receives an already-hashed validator. Storage never receives the original validator from the browser cookie.

[`models/MemoryTokenStorage.cfc`](models/MemoryTokenStorage.cfc) is the shortest complete example. [`models/SQLTokenStorage.cfc`](models/SQLTokenStorage.cfc) shows a persistent implementation.

Make a stateful provider a singleton. For example, memory storage must be a singleton so each request uses the same in-memory struct. A provider that sends each operation to a database does not need to be a singleton.

## The `onRecall` interception point

RememberMe announces `onRecall` after it validates a token and loads the user. The interception data has two values:

| Name | Value |
| --- | --- |
| `user` | The value returned by `retrieveUserById()`. |
| `userId` | The numeric user ID stored with the token. |

Add an `onRecall()` method to a registered ColdBox interceptor to listen for the event:

```cfc
component {

    function onRecall( event, interceptData ) {
        var recalledUser = arguments.interceptData.user;
        var recalledUserId = arguments.interceptData.userId;

        // Add audit logging or other app-specific work here.
    }

}
```

The event does not run when RememberMe rejects a token.

## Upgrade from RememberMe 1.x

RememberMe 2.0 removed its required qb dependency. The default provider is now `SQLTokenStorage@rememberMe`, which uses `queryExecute()`.

- If you did not set `tokenStorageClass`, you do not need to change your configuration or database. The new provider uses the same table and columns.
- If you set `tokenStorageClass = "QBTokenStorage@rememberMe"`, install qb in your app with `box install qb`.
- If your app used qb only because RememberMe installed it, add qb to your app's own `box.json` before your next install.
- If you use a custom storage provider, the seven-method storage contract has not changed.

The 2.0 storage change does not change the cookie format or database schema. Existing RememberMe tokens remain valid.

## First-request helper error

Some apps call `remember()` from `onSessionStart()` before ColdBox has loaded application helpers. In that case, the first request may report that `remember` does not exist.

Run recall logic from a `preProcess()` interceptor instead of `onSessionStart()`. The recall example in this guide uses `preProcess()` for this reason.

## License

RememberMe is available under the [MIT License](LICENSE.md).
