/**
 * Manages remember-me cookies and stored tokens.
 *
 * A token has a selector and a validator. The selector finds the stored token record. The
 * validator proves that the browser cookie matches that record. The encrypted browser cookie
 * contains the raw validator, but the storage provider receives only its hash.
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
     * Validates the remember-me cookie and returns the matching user.
     *
     * The configured user service decides what to return when the user ID does not exist. Callers
     * should check the returned value as required by that user service.
     *
     * @return The value returned by the configured user service.
     * @throws MissingCookie When the request has no usable remember-me cookie.
     * @throws InvalidToken When the cookie is malformed, unknown, forged, or expired.
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

        // Reject the token if storage has no matching selector, the validator is wrong, or the
        // stored token has expired.
        if ( 
            rememberMe.isEmpty() || 
            !isMatch( parsedToken.hashedValidator, rememberMe.hashedValidator ) ||
            rememberMe.expirationDate <= now()
        ) {
            throw( type="InvalidToken", message="Invalid remember me token" );
        }

        // Build the audit values here so every storage provider records the same information.
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
     * Creates a stored token and a browser cookie for the user.
     *
     * @userId The ID of the user to remember.
     */
    void function rememberMe( required numeric userId ) {

        // Remove the current cookie and its stored token before creating a replacement.
        forgetMe();

        // Put the raw validator in the encrypted cookie. Store only the validator hash. A person
        // who steals the stored data cannot use the hash as a valid cookie value.
        var validator = createUuid();

        // Build every value in the service, including all dates. A storage provider only saves the
        // completed values and never receives the raw validator.
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

        // Use cfcookie() with a date for expires because Adobe ColdFusion, Lucee, and BoxLang all
        // support this form. Assigning a settings struct to the cookie scope only works in Lucee.
        // BoxLang also rejects a number of days as the expires value.
        var cookieAttributes = {
            name         : variables._cookieName,
            value        : encryptToken( rememberMe.selector & "_" & validator ),
            expires      : dateAdd( "d", variables.settings.days, now() ),
            httpOnly     : true,
            secure       : booleanFormat( cgi.SERVER_PORT_SECURE ),
            sameSite     : "lax",
            preserveCase : true
        };

        // Adobe ColdFusion requires a domain when cfcookie() receives a path. A domain cookie would
        // cover more hosts than needed. Adobe ColdFusion uses its default path of / instead.
        if ( !findNoCase( "ColdFusion", server.coldfusion.productname ) ) {
            cookieAttributes.path = "/";
        }

        cfcookie( attributeCollection = cookieAttributes );

    }


    /**
     * Deletes the current stored token and expires the browser cookie.
     *
     * A missing or malformed cookie has no selector that can be deleted. The browser cookie is
     * still expired in both cases.
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
     * Deletes the stored record named by an encrypted token.
     *
     * @token An encrypted token that contains a selector and a validator.
     */
    void function expireToken( required string token ) {
        getTokenStorage().deleteBySelector( parseToken( arguments.token ).selector );
    }


    /**
     * Deletes every stored token for one user.
     *
     * @userId The ID of the user whose tokens will be deleted.
     */
    void function deleteByUserId( required numeric userId ) {
        getTokenStorage().deleteByUserId( arguments.userId );
    }


    /**
     * Deletes every stored token.
     *
     * Use this method when all remembered users must sign in again, such as after changing the
     * token algorithm or encryption key.
     */
    void function deleteAll() {
        getTokenStorage().deleteAll();
    }


    /**
     * Deletes tokens that have been expired longer than the grace period.
     *
     * The module scheduler calls this method each day. For example, a grace period of one day keeps
     * a token record until one day after the token expires.
     *
     * @graceDays The number of days to keep an expired record. Defaults to the purgeGraceDays setting.
     * @return The number of deleted token records.
     */
    numeric function purgeExpired( numeric graceDays ) {

        if ( isNull( arguments.graceDays ) ) {
            arguments.graceDays = variables.settings.purgeGraceDays;
        }

        // Calculate the cutoff here so storage providers do not need to know the purge policy.
        return getTokenStorage().deleteExpiredBefore( dateAdd( "d", -arguments.graceDays, now() ) );
    }


    /**
     * Returns the stored token with the given selector.
     *
     * @selector The unique value used to find a stored token.
     * @return The stored token, or an empty struct when no token matches.
     */
    struct function getBySelector( required string selector ) {
        // Handle an empty selector here. Storage providers can assume that every selector they
        // receive contains a value.
        return len( arguments.selector ) ? getTokenStorage().getBySelector( arguments.selector ) : {};
    }


    /**
     * Returns the encrypted token from the request's remember-me cookie.
     *
     * Call cookieExists() first because this method expects the cookie to exist.
     *
     * @return The encrypted token stored in the cookie.
     */
    string function getCookie() {
        return cookie[ variables._cookieName ];
    }


    /**
     * Hashes a raw validator with the configured hash algorithm.
     *
     * @validator The raw validator from a new token or a decrypted cookie.
     * @return The validator hash used for storage and comparison.
     */
    private function hashValidator( required string validator ) {
        return hash( arguments.validator, settings.validatorHashAlgorithm );
    }


    /**
     * Decrypts a cookie token and separates its selector from its validator.
     *
     * The returned struct contains the validator hash, not the raw validator.
     *
     * @token The encrypted token from the remember-me cookie.
     * @return A struct containing selector and hashedValidator.
     */
    private struct function parseToken( required string token ) {
        
        var tokenArray = listToArray( decryptToken( arguments.token ), "_" );
        
        return {
            "selector" = tokenArray[ 1 ],
            "hashedValidator" = hashValidator( tokenArray[ 2 ] )
        };

    }


    /**
     * Returns whether a token can be decrypted and contains both required parts.
     *
     * This check does not read storage. It does not prove that the token exists, matches a stored
     * validator, or has not expired.
     *
     * @token The encrypted token to check.
     * @return True when the token has a valid format. Otherwise, false.
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
     * Returns whether the request contains a usable remember-me cookie.
     *
     * An empty cookie counts as missing. Adobe ColdFusion leaves an expired cookie key in the
     * request cookie scope with an empty value. Lucee and BoxLang remove the key.
     *
     * @return True when the cookie exists and contains a value. Otherwise, false.
     */
    boolean function cookieExists() {
        return cookie.keyExists( variables._cookieName ) && len( cookie[ variables._cookieName ] );
    }


	/**
	 * Returns the configured user service.
	 *
	 * WireBox is ColdBox's dependency injection system. WireBox resolves the service only on the
	 * first call. This RememberMeService instance reuses the resolved service on later calls.
	 *
	 * @return The configured user service.
	 * @throws IncompleteConfiguration When userServiceClass is empty.
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
	 * Returns the configured token storage provider.
	 *
	 * A storage provider saves and loads token records. The default SQLTokenStorage provider uses
	 * queryExecute() and needs no extra package. MemoryTokenStorage is for development and tests.
	 * QBTokenStorage is optional and requires qb. Custom providers must follow ITokenStorage.cfc.
	 *
	 * WireBox resolves the provider only on the first call. This RememberMeService instance reuses
	 * the resolved provider on later calls.
	 *
	 * @return The configured token storage provider.
	 * @throws IncompleteConfiguration When tokenStorageClass is empty.
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
     * Decrypts a remember-me token with the configured key and algorithm.
     *
     * @token The encrypted token from the browser cookie.
     * @return The plain selector and validator string.
     */
    private function decryptToken( required string token ) {
        return decrypt( arguments.token, settings.tokenEncryptKey, settings.tokenEncryptAlgorithm, "Base64" );
    }

    
    /**
     * Encrypts a remember-me token with the configured key and algorithm.
     *
     * @token The plain selector and validator string.
     * @return The encrypted value to store in the browser cookie.
     */
    private function encryptToken( required string token ) {
        return encrypt( arguments.token, settings.tokenEncryptKey, settings.tokenEncryptAlgorithm, "Base64" );
    }


    /**
     * Returns whether a validator hash matches the stored validator hash.
     *
     * @challenger The validator hash created from the browser cookie.
     * @hashedValidator The validator hash read from storage.
     * @return True when both hashes are equal. Otherwise, false.
     */
    private function isMatch( required string challenger, required string hashedValidator ) {
        return ( compare( arguments.hashedValidator, arguments.challenger ) == 0 );
    }

    

}
