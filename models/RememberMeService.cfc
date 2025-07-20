/**
* RememberMeService
* 
* token: a string stored in the user's cookie scope. This is thier key for re-entry
*/
component 
    hint="I am the user remember service. I deal with recalling user entities based on a special 'remember' cookie"
{
    
    property name="wirebox" inject="wirebox";
    property name="settings" inject="coldbox:modulesettings:rememberMe";
    property name="userServiceClass" inject="coldbox:modulesettings:rememberMe:userServiceClass";
    property name="qb" inject="provider:QueryBuilder@qb";
    property name="interceptorService" inject="coldbox:interceptorService";


    variables._table = "user_remember";
    variables._cookieName = "rememberMe-#application.applicationName#";
    
    
    /**
     * Recall User
     * Returns a User entity based on a token.  
     * You should perform some type of `isLoaded()` check on the returned entity to ensure a matching record was found
     */
    any function recallMe() {
        
        if ( !cookieExists() ) {
            throw( "missing userRemember cookie", "MissingCookie" );
        }

        var token = getCookie();

        if ( !isValidToken( token ) ) {
            throw( "invalid userRemember token", "InvalidToken" );
        }
        
        var parsedToken = parseToken( token );
        var rememberMe = getBySelector( parsedToken.selector );

        // if we didn't find a match, if the validator isn't a match, or if the token is expired throw an error
        if ( 
            rememberMe.isEmpty() || 
            !isMatch( parsedToken.hashedValidator, rememberMe.hashedValidator ) ||
            rememberMe.expirationDate <= now()
        ) {
            throw( type="InvalidToken", message="Invalid remember me token" );
        }

        // Update the database
        qb.from( variables._table )
            .whereId( rememberMe.id )
            .update( {
                ipAddress = { value = cgi.REMOTE_HOST, cfsqltype = "varchar" },
                userAgent = { value = cgi.HTTP_USER_AGENT, cfsqltype = "varchar" },
                lastUsedDate = { value = now(), cfsqltype = "timestamp" },
                modifiedDate = { value = now(), cfsqltype = "timestamp" }
            } )
        ;

        var user = getUserService().retrieveUserById( rememberMe.userId );

        variables.interceptorService.announce( "onRecall", { 
            "user": user, 
            "userId": rememberMe.userId 
        } );

        return user;

    }


    /**
     * RememberMe
     * Remembers user for future sessions to automatically log them in
     * This method persists the rememberMe credentials and stores a cookie on the visitors browser
     *
     * @userId: the id for the user we want to remember 
     */
    void function rememberMe( required numeric userId ) {

        // expire any old cookie
        forgetMe();

        var rememberMe = {
            "userId": arguments.userId,
            "selector": createUuid(),
            "hashedValidator": hashValidator( createUuid() )
        };

        qb.from( variables._table )
            .insert( {
                userId: arguments.userId,
                selector: rememberMe.selector,
                hashedValidator: rememberMe.hashedValidator,
                ipAddress = { value = cgi.REMOTE_HOST, cfsqltype = "varchar" },
                userAgent = { value = cgi.HTTP_USER_AGENT, cfsqltype = "varchar" },
                createdDate = { value = now(), cfsqltype = "timestamp" },
                expirationDate = { value = dateAdd( 'd', variables.settings.days, now() ), cfsqltype = "timestamp" }
            } )
        ;

        cookie[ variables._cookieName ] = {
            httpOnly = "true",
            preserveCase = "true",
            secure = booleanFormat( cgi.SERVER_PORT_SECURE ),
            expires = variables.settings.days,
            sameSite = "lax",
            path = "/",
            value = encryptToken( rememberMe.selector & "_" & rememberMe.hashedValidator )
        };

    }


    /**
     * forgetMe
     * Purges a token from the datasource as well as removes the cookie from the visitors browser
     */
    void function forgetMe() {

        if ( 
            cookieExists() && 
            isValidToken( getCookie() )    
        ) {
            expireToken( getCookie() );
        }
        
        cfcookie(
            name=variables._cookieName,
            expires="now",
            preserveCase=true
        ); 

        cookie.delete( variables._cookieName );

    }


    /**
     * Expire Token
     * Deletes references to a selector based on a passed token. 
     * 
     * @token
     */
    void function expireToken( required string token ) {
        qb.from( variables._table ).where( "selector", parseToken( arguments.token ).selector ).delete();
    }


    /**
     * Delete By User Id
     * Deletes all remembered selectors based on a given userId
     * 
     * @userId
     */
    void function deleteByUserId( required numeric userId ) {
        qb.from( variables._table ).where( "userId", arguments.userId ).delete();
    }


    /**
     * Delete All
     * Deletes all userRemember records. Useful if the token algorithm changes and you want to log everyone out
     *
     * @token 
     */
    void function deleteAll() {
        qb.from( variables._table ).delete();
    }


    /**
     * getBySelector
     * Returns the remember me struct based on the selector value
     *
     * @selector 
     */
    struct function getBySelector( required string selector ) {
        return ( 
            len( arguments.selector ) ? 
                qb
                    .select()
                    .from( variables._table )
                    .where( "selector", "=", { 
                        value = arguments.selector, 
                        cfsqltype = "varchar" 
                } ).first() : 
                {} 
            )
        ;
    }


    /**
     * getCookie
     * Returns the cookie value from the browser.  
     */
    string function getCookie() {
        return cookie[ variables._cookieName ];
    }


    /**
     * hashValidator
     * Hashes the validator string for extra security
     *
     * @validator 
     */
    private function hashValidator( required string validator ) {
        return hash( arguments.validator, settings.validatorHashAlgorithm );
    }


    /**
     * parseToken
     * Parses the token received from a cookie into the appropriate parts (selector, hashedValidator)
     * 
     * @token 
     */
    private struct function parseToken( required string token ) {
        
        var tokenArray = listToArray( decryptToken( arguments.token ), "_" );
        
        return {
            "selector" = tokenArray[ 1 ],
            "hashedValidator" = hashValidator( tokenArray[ 2 ] )
        };

    }


    /**
     * Returns whether the token appears to be in a valid format. 
     * This does NOT check the database and instead only validates the token itself
     *
     * @token 
     */
    boolean function isValidToken( required string token ) {
        
        try {
            var parsedToken = parseToken( arguments.token );
        } catch ( any e ) {
            return false;
        }

        return booleanFormat(
            len( parsedToken.selector ) && 
            len( parsedToken.hashedValidator )
        );

    }


    /**
     * Cookie Exists?
     * Returns true/false whether the remember me cookie exists in the browser
     */
    boolean function cookieExists() {
        return cookie.keyExists( variables._cookieName );
    }


    /**
	 * getUserService
     * Get the appropriate user service configured by the settings
     * inspired by cbAuth
	 *
	 * @throws IncompleteConfiguration
	 */
	private any function getUserService() {
		if ( !structKeyExists( variables, "userService" ) ) {
			if ( variables.userServiceClass == "" ) {
				throw(
					type    = "IncompleteConfiguration",
					message = "No [userServiceClass] provided.  Please set in `config/ColdBox.cfc` under `moduleSettings.rememberMe.userServiceClass`."
				);
			}

			variables.userService = variables.wirebox.getInstance( dsl = variables.userServiceClass );
		}

		return variables.userService;
	}


    /**
     * decryptToken
     * Decrypts a rememberMe token string
     */
    private function decryptToken( required string token ) {
        return decrypt( arguments.token, settings.tokenEncryptKey, settings.tokenEncryptAlgorithm, "Base64" );
    }

    
    /**
     * encryptToken
     * Encrypts a rememberMe token string
     */
    private function encryptToken( required string token ) {
        return encrypt( arguments.token, settings.tokenEncryptKey, settings.tokenEncryptAlgorithm, "Base64" );
    }


    /**
     * isMatch
     * Checks to see if a challenger string exactly matches the hashedvalidator value
     */
    private function isMatch( required string challenger, required string hashedValidator ) {
        return ( compare( arguments.hashedValidator, arguments.challenger ) != 0 );
    }

    

}