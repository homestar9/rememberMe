# RememberMe

![RememberMe icon](https://github.com/homestar9/rememberMe/blob/master/rememberMe.svg?raw=true)

RememberMe is a Coldbox module designed to work in conjunction with your authentication system to "remember" and automatically log in users on subsequent website visits.  

## Engine Support

- Lucee 5+
- Adobe ColdFusion 2023+
- Boxlang 1+

## Requirements

- Coldbox 8+
- Cbauth or your own authentication provider

## Installation

Within Commandbox type:
```
box install rememberMe
```

Copy over the configuration object below into your `/config/Coldbox.cfc` `moduleSettings` section. 

```
rememberMe = {
    userServiceClass = "",
    tokenEncryptKey = "",
    days = 30,
    autoPurge = true,       // daily scheduled purge of stale token rows (see "Automatic purging")
    purgeGraceDays = 1,     // keep rows this many days past expiration; 0 = purge immediately on expiry
    purgeTime = "04:00",    // daily purge run time, 24h server time
    table = "user_remember", // token table used by the default storage
    datasource = "",        // "" = your app's default datasource (this.datasource in Application.cfc)
    tokenStorageClass = "QBTokenStorage@rememberMe" // swap in your own storage (see "Custom token storage")
}
```
You will need to specify a `userServiceClass` that implements the method `retrieveUserById()`.  You will also need to generate a unique encryption key that will be used when generating tokens.  Hint: You can generate a valid random key by executing the following code `generateSecretKey("AES", 256)`.

Make sure your CFML datasource has a database table with the following columns (currently tested with MSSQL Server). The table name defaults to `user_remember` and is configurable via the `table` setting; the `datasource` setting lets you keep token rows in a different datasource entirely (empty means your application default):
| column name     | type      |
|-----------------|----------|
| id              | int      |
| createdDate     | datetime |
| modifiedDate    | datetime |
| userId          | int      |
| selector        | varchar(35)|
| hashedValidator | varchar(32)|
| ipAddress       | varchar(45)|
| userAgent       | varchar(255)|
| expirationDate  | datetime |
| lastUsedDate    | datetime |

## Usage

RememberMe automatically injects a `remember()` helper into all Coldbox interceptors.  Here's an example of how you might utilize RememberMe on the Coldbox `preProcess()` interceptor method on an app that uses cbauth for their authentication provider:

```

function preProcess( event, interceptData, buffer, rc, prc ) {
    
    // if the user is not logged in, and the rememberMe cookie exists, attempt to recall the user
    if ( 
        !auth().isLoggedIn() && // <-- cbAuth method
        remember().cookieExists() 
    ) {
        
        try {
            
            // attempt to recall the user 
            // if successful, returns a user object from your `userServiceClass`
            var user = remember().recallMe();

            // verify the user exists and log them in using cbauth
            if ( user.isLoaded() ) {
                auth().login( user ); // <-- cbAuth method
            }

        // if the token is invalid, forget the user and cleanup bad cookies
        } catch( InvalidToken e ) {
            remember().forgetMe();
        }

    }
```

## Automatic purging

Expired tokens are already unusable — `recallMe()` rejects them — but their rows would otherwise sit in the table forever. The module registers a ColdBox scheduled task (`rememberMe-purge-expired-tokens`) that runs daily at `purgeTime` and deletes rows whose `expirationDate` passed more than `purgeGraceDays` days ago. The grace period keeps recently-expired rows around briefly in case you want them for auditing.

- **It is on by default.** Set `autoPurge = false` in your module settings to disable it; the task stays registered but does nothing.
- You can also purge manually (for example from your own scheduled task or a maintenance script):

```cfc
getInstance( "RememberMeService@rememberMe" ).purgeExpired();     // uses purgeGraceDays
getInstance( "RememberMeService@rememberMe" ).purgeExpired( 0 );  // purge everything already expired
```

`purgeExpired()` returns the number of rows deleted.

- **Clustering note:** the task runs on every node. That is deliberate — constraining it to one server requires a distributed CacheBox region, and a concurrent double-run of this DELETE is harmless (it is idempotent).
- `purgeTime` is interpreted in the server's timezone.

## Custom token storage

By default the module persists tokens itself with [qb](https://qb.ortusbooks.com/) (`models/QBTokenStorage.cfc`), against the `table` and `datasource` settings above. If that doesn't fit — you want your ORM, a separate token store, Redis, anything — point `tokenStorageClass` at any WireBox-resolvable class of your own:

```cfc
rememberMe = {
    ...
    tokenStorageClass = "TokenStorage" // resolved via WireBox, like userServiceClass
}
```

Your class must satisfy the contract in `interfaces/ITokenStorage.cfc` (the shipped `models/QBTokenStorage.cfc` is the reference implementation):

| method | arguments | returns |
| --- | --- | --- |
| `create` | `token` struct: `userId`, `selector`, `hashedValidator`, `ipAddress`, `userAgent`, `createdDate`, `modifiedDate`, `expirationDate` | — |
| `getBySelector` | `selector` | struct with at least `userId`, `selector`, `hashedValidator`, `expirationDate` — **empty struct** when not found, never null |
| `updateUsage` | `selector`, `audit` struct: `ipAddress`, `userAgent`, `lastUsedDate`, `modifiedDate` | — |
| `deleteBySelector` | `selector` | — |
| `deleteByUserId` | `userId` | — |
| `deleteAll` | — | — |
| `deleteExpiredBefore` | `cutoffDate` | number of rows deleted (0 if unknown) |

Two guarantees make implementations simple and safe:

- **Everything is a plain value** (strings, numerics, native dates). The service computes all of it — dates included — so storage holds no policy.
- **Storage never sees a raw validator.** All crypto happens in the service before storage is called; you only ever store the selector and the already-hashed validator, so a custom provider cannot weaken the token scheme.

## Known Issues

Sometimes the first load of an app will throw an error stating that `remember` cannot be found.  I believe this has to do with a "chicken and egg" problem where sometimes every Coldbox dependency is loaded when the first `onSessionStart()` method executes.  I recommend using `preProcess()` instead of `onSessionStart()` to avoid this issue for now.

## Intercetion Points

### onRecall

This is a custom interception point that fires when the `remember().recall()` method is called. You can use this to add custom logic, such as logging or additional processing, during the recall process.

#### InterceptData

| Name          | Description                                                                 |
|---------------|-----------------------------------------------------------------------------|
| user          | The user object returned by the `remember().recall()` method.              |
| userId       | The ID of the user returned by the `remember().recall()` method.           |


## Future Development Roadmap

- Get community feedback for improving the module and documentation.
- Automatically create table in datasource if missing.
