# RememberMe

RememberMe is a Coldbox module designed to work in conjunction with your authentication system to "remember" and automatically log in users on subsequent website visits.  

## Requirements

 - Lucee 5+
 - Adobe ColdFusion 2016+
 - Coldbox 6+
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
    days = 30
}
```
You will need to specify a `userServiceClass` that implements the method `getById()`.  You will also need to generate a unique encryption key that will be used when generating tokens.  Hint: You can generate a valid random key by executing the following code `generateSecretKey("AES", 256)`.

Make sure your CFML datasource has a database table with the following columns (currently tested with MSSQL Server):
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

RememberMe automatically injects a `remember()` helper into all Coldbox interceptors.  Here's an example of how you might utilize RememberMe on the `onSessionStart()` interceptor method on an app that uses cbauth for their authentication provider:

```
/**
* SessionStart
* Triggers when a new session begins
*
* @sessionStruct 
*/
function sessionStart( sessionStruct ) {
    
    // Use the helper method to see if the right cookie exists in the browser
    if ( remember().cookieExists() ) {
        
        try {
            
            // attempt to recall the user 
            // if successful, returns a user object from your `userServiceClass`
            var user = remember().recallMe();

            // verify the user exists and log them in using cbauth
            if ( user.isLoaded() ) {
                auth().login( user );
            }

        // if the token is invalid, forget the user and cleanup bad cookies
        } catch( InvalidToken e ) {
            remember().forgetMe();
        }

    }
```

## Known Issues

Sometimes the first load of an app will throw an error stating that `remember` cannot be found.  I believe this has to do with a "chicken and egg" problem where sometimes every Coldbox dependency is loaded when the first `onSessionStart()` method executes.  I am open to suggestions for how to work around this.

## Future Development Roadmap

 - Testbox integration + test-harness setup.
 - Get community feedback for improving the module and documentation.
 - Automatically create table in datasource if missing.
 - Ability to customize the table name based on config.
 - Learn how to implement building/versioning like other Coldbox modules.
 - Utilize some interceptor methods for custom behavior.
 - Add some type of database cleanup operation to purge old records