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
    property name="tokenStorageClass" inject="coldbox:modulesettings:rememberMe:tokenStorageClass";
    property name="interceptorService" inject="coldbox:interceptorService";


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

        // Stamp the audit columns. The service assembles the values — storage just persists them.
        getTokenStorage().updateUsage( parsedToken.selector, {
            "ipAddress": cgi.REMOTE_HOST,
            "userAgent": cgi.HTTP_USER_AGENT,
            "lastUsedDate": now(),
            "modifiedDate": now()
        } );

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

        // The cookie carries the RAW validator; the database stores only its hash. That asymmetry
        // is the entire point of the selector/validator scheme: a leaked database gives an
        // attacker hashes it cannot present back to us.
        var validator = createUuid();

        // The service computes every value — dates included — so a storage provider is a dumb
        // persister with no policy of its own. Note storage receives the HASHED validator only.
        var rememberMe = {
            "userId": arguments.userId,
            "selector": createUuid(),
            "hashedValidator": hashValidator( validator ),
            "ipAddress": cgi.REMOTE_HOST,
            "userAgent": cgi.HTTP_USER_AGENT,
            "createdDate": now(),
            "modifiedDate": now(),
            "expirationDate": dateAdd( 'd', variables.settings.days, now() )
        };

        getTokenStorage().create( rememberMe );

        // cfcookie() with a DateTime `expires` is the one form every engine agrees on: assigning
        // an attribute struct to the cookie scope is Lucee-only (ACF's scope can't clear it,
        // BoxLang rejects an integer day-count for expires).
        var cookieAttributes = {
            name         : variables._cookieName,
            value        : encryptToken( rememberMe.selector & "_" & validator ),
            expires      : dateAdd( "d", variables.settings.days, now() ),
            httpOnly     : true,
            secure       : booleanFormat( cgi.SERVER_PORT_SECURE ),
            sameSite     : "lax",
            preserveCase : true
        };

        // Adobe's cfcookie only accepts `path` alongside `domain`, and a domain cookie is broader
        // than we want — so on ACF the cookie keeps the browser's default path instead.
        if ( !findNoCase( "ColdFusion", server.coldfusion.productname ) ) {
            cookieAttributes.path = "/";
        }

        cfcookie( attributeCollection = cookieAttributes );

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

        structDelete( cookie, variables._cookieName );

    }


    /**
     * Expire Token
     * Deletes references to a selector based on a passed token. 
     * 
     * @token
     */
    void function expireToken( required string token ) {
        getTokenStorage().deleteBySelector( parseToken( arguments.token ).selector );
    }


    /**
     * Delete By User Id
     * Deletes all remembered selectors based on a given userId
     * 
     * @userId
     */
    void function deleteByUserId( required numeric userId ) {
        getTokenStorage().deleteByUserId( arguments.userId );
    }


    /**
     * Delete All
     * Deletes all userRemember records. Useful if the token algorithm changes and you want to log everyone out
     *
     * @token 
     */
    void function deleteAll() {
        getTokenStorage().deleteAll();
    }


    /**
     * Purge Expired
     * Deletes rows whose expirationDate passed more than graceDays ago
     * ( expirationDate < now() - graceDays ). Run daily by the module scheduler.
     *
     * @graceDays Days past expiration to retain rows. Defaults to the purgeGraceDays setting.
     *
     * @return The number of rows deleted
     */
    numeric function purgeExpired( numeric graceDays ) {

        if ( isNull( arguments.graceDays ) ) {
            arguments.graceDays = variables.settings.purgeGraceDays;
        }

        // Grace-period policy lives here; storage just deletes everything expired before a date.
        return getTokenStorage().deleteExpiredBefore( dateAdd( "d", -arguments.graceDays, now() ) );
    }


    /**
     * getBySelector
     * Returns the remember me struct based on the selector value
     *
     * @selector 
     */
    struct function getBySelector( required string selector ) {
        // The empty-selector short-circuit stays HERE, so storage providers may assume a
        // non-empty selector (interfaces/ITokenStorage.cfc documents that guarantee).
        return len( arguments.selector ) ? getTokenStorage().getBySelector( arguments.selector ) : {};
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
     * Returns true/false whether the remember me cookie exists in the browser.
     * An empty value counts as absent: Adobe CF never removes an expired cookie's key from the
     * in-request cookie scope — it leaves it behind with an empty value — and an empty token is
     * unusable anyway.
     */
    boolean function cookieExists() {
        return cookie.keyExists( variables._cookieName ) && len( cookie[ variables._cookieName ] );
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
	 * getTokenStorage
	 * Get the token storage provider configured by the settings. Defaults to the module's own
	 * qb-backed QBTokenStorage; see interfaces/ITokenStorage.cfc for the contract a custom
	 * provider must satisfy.
	 *
	 * @throws IncompleteConfiguration
	 */
	private any function getTokenStorage() {
		if ( !structKeyExists( variables, "tokenStorage" ) ) {
			if ( variables.tokenStorageClass == "" ) {
				throw(
					type    = "IncompleteConfiguration",
					message = "No [tokenStorageClass] provided.  Please set in `config/ColdBox.cfc` under `moduleSettings.rememberMe.tokenStorageClass`."
				);
			}

			variables.tokenStorage = variables.wirebox.getInstance( dsl = variables.tokenStorageClass );
		}

		return variables.tokenStorage;
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
        return ( compare( arguments.hashedValidator, arguments.challenger ) == 0 );
    }

    

}