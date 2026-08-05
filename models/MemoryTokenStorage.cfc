/**
 * Stores remember-me tokens in the application's memory.
 *
 * A storage provider saves, loads, updates, and deletes token records for RememberMeService. This
 * provider follows ITokenStorage.cfc and does not need a database. Use it for local development,
 * automated tests, or trying the module before the token table exists. This file is also a small
 * example for developers who want to build a custom storage provider.
 *
 * Do not use this provider in production. An application restart or a restart of the Java process,
 * called the JVM, deletes every token. The user must sign in again after the tokens are lost.
 * Servers also do not share this data. In a group of servers, only the server that created a token
 * can recall that token.
 *
 * ModuleConfig maps this provider as a singleton. A singleton is one shared instance. A new
 * instance would start with an empty struct, so later requests could not recall saved tokens.
 */
component
    hint="I am an in-memory token storage provider for the rememberMe module. Development and tests only — tokens do not survive an application restart."
{

    variables.tokens = {};

    // A named lock prevents requests from changing the token struct at the same time. Lock names
    // are shared across the JVM, so include the application name to keep each application's lock
    // separate.
    variables._lockName = "rememberMe-MemoryTokenStorage-#application.applicationName#";


    /**
     * Saves a new token in memory.
     *
     * Store a copy so later changes to the caller's struct do not change the saved token.
     *
     * @token The complete token struct to save. It must contain userId, selector,
     *        hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, and expirationDate.
     */
    void function create( required struct token ) {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            variables.tokens[ arguments.token.selector ] = duplicate( arguments.token );
        }
    }


    /**
     * Returns the token with the given selector.
     *
     * The returned token is a copy. A caller cannot change the saved token by changing the copy.
     *
     * @selector The unique value used to find a stored token.
     * @return A copy of the stored token, or an empty struct when no token matches.
     */
    struct function getBySelector( required string selector ) {
        lock name="#variables._lockName#" type="readonly" timeout="10" {
            // ITokenStorage requires an empty struct when no token matches.
            return structKeyExists( variables.tokens, arguments.selector )
                 ? duplicate( variables.tokens[ arguments.selector ] )
                 : {};
        }
    }


    /**
     * Updates the audit fields after a successful token recall.
     *
     * Audit fields describe the request that used the token and the time of that use. Other token
     * fields stay unchanged. An unknown selector does nothing, which matches a database update
     * that finds no record.
     *
     * @selector The unique value used to find the stored token.
     * @audit A struct containing ipAddress, userAgent, lastUsedDate, and modifiedDate.
     */
    void function updateUsage( required string selector, required struct audit ) {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            if ( structKeyExists( variables.tokens, arguments.selector ) ) {
                structAppend( variables.tokens[ arguments.selector ], arguments.audit, true );
            }
        }
    }


    /**
     * Deletes the token with the given selector.
     *
     * @selector The unique value used to find a stored token.
     */
    void function deleteBySelector( required string selector ) {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            structDelete( variables.tokens, arguments.selector );
        }
    }


    /**
     * Deletes every token for one user.
     *
     * Loop over a separate array of selector keys. Some CFML engines cannot safely delete entries
     * from a struct while code loops over that same struct.
     *
     * @userId The ID of the user whose tokens will be deleted.
     */
    void function deleteByUserId( required numeric userId ) {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            for ( var selector in structKeyArray( variables.tokens ) ) {
                if ( variables.tokens[ selector ].userId == arguments.userId ) {
                    structDelete( variables.tokens, selector );
                }
            }
        }
    }


    /**
     * Deletes every token from memory.
     */
    void function deleteAll() {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            variables.tokens = {};
        }
    }


    /**
     * Deletes tokens that expired before the cutoff date.
     *
     * Use dateCompare() because some CFML engines may treat the less-than operator as a text
     * comparison for dates. A text comparison does not always put dates in the correct order.
     *
     * @cutoffDate Delete tokens with an expirationDate before this date.
     * @return The number of deleted tokens.
     */
    numeric function deleteExpiredBefore( required date cutoffDate ) {

        var deleted = 0;

        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            for ( var selector in structKeyArray( variables.tokens ) ) {
                if ( dateCompare( variables.tokens[ selector ].expirationDate, arguments.cutoffDate ) < 0 ) {
                    structDelete( variables.tokens, selector );
                    deleted++;
                }
            }
        }

        return deleted;
    }


    /**
     * Returns the number of tokens currently stored in memory.
     *
     * count() is a development and test helper. It is not part of ITokenStorage.cfc, so custom
     * storage providers do not need to implement it.
     *
     * @return The number of stored tokens.
     */
    numeric function count() {
        lock name="#variables._lockName#" type="readonly" timeout="10" {
            return structCount( variables.tokens );
        }
    }

}
