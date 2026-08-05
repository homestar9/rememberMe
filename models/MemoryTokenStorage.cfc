/**
 * MemoryTokenStorage
 *
 * A token storage provider that keeps every token in a struct in memory. It satisfies
 * interfaces/ITokenStorage.cfc completely, in about forty lines, with no database and no
 * dependencies — which makes it two useful things at once:
 *
 *  1. A working store for development, for automated tests, and for trying the module out before
 *     you have created the token table.
 *  2. The shortest complete example to copy when you write your own provider. Read this file
 *     alongside interfaces/ITokenStorage.cfc, then swap the struct for your ORM, your cache, your
 *     Redis client, or whatever you actually persist to.
 *
 * DO NOT USE THIS IN PRODUCTION. Tokens live in one application's memory, so:
 *
 *  - every token is lost when the application restarts or the JVM recycles, and every remembered
 *    user is silently logged out;
 *  - nothing is shared between servers, so in a cluster a user is only remembered on the one node
 *    that issued the cookie.
 *
 * Neither of those is a security hole — a lost token just means the user logs in again — but both
 * make "remember me" look broken. Use SQLTokenStorage@rememberMe (the default) or your own
 * provider for anything real.
 *
 * This is mapped `asSingleton` in ModuleConfig.onLoad(). That is not a style choice: every other
 * mapping in this module is a transient, and a transient in-memory store would be rebuilt empty on
 * every injection, so nothing could ever be recalled.
 */
component
    hint="I am an in-memory token storage provider for the rememberMe module. Development and tests only — tokens do not survive an application restart."
{

    variables.tokens = {};

    // Named locks are JVM-wide, so scope this one to the application. Same idiom RememberMeService
    // uses for its cookie name.
    variables._lockName = "rememberMe-MemoryTokenStorage-#application.applicationName#";


    /**
     * create
     * Persists a new token. The service supplies every value, dates included.
     *
     * duplicate() so a caller that hangs on to the struct it passed in cannot mutate what we hold.
     *
     * @token { userId, selector, hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, expirationDate }
     */
    void function create( required struct token ) {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            variables.tokens[ arguments.token.selector ] = duplicate( arguments.token );
        }
    }


    /**
     * getBySelector
     * Returns the token struct for a selector, or an empty struct when there is no match.
     *
     * @selector
     */
    struct function getBySelector( required string selector ) {
        lock name="#variables._lockName#" type="readonly" timeout="10" {
            // The contract is an EMPTY STRUCT on no match — never null.
            return structKeyExists( variables.tokens, arguments.selector )
                 ? duplicate( variables.tokens[ arguments.selector ] )
                 : {};
        }
    }


    /**
     * updateUsage
     * Stamps the audit keys on a token that was just recalled, leaving everything else alone.
     * Silently does nothing if the selector is unknown, which matches what an UPDATE ... WHERE
     * against a missing row would do.
     *
     * @selector
     * @audit { ipAddress, userAgent, lastUsedDate, modifiedDate }
     */
    void function updateUsage( required string selector, required struct audit ) {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            if ( structKeyExists( variables.tokens, arguments.selector ) ) {
                structAppend( variables.tokens[ arguments.selector ], arguments.audit, true );
            }
        }
    }


    /**
     * deleteBySelector
     *
     * @selector
     */
    void function deleteBySelector( required string selector ) {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            structDelete( variables.tokens, arguments.selector );
        }
    }


    /**
     * deleteByUserId
     * Iterate a KEY ARRAY rather than the struct itself — deleting from a struct you are looping
     * over is undefined behaviour on some engines.
     *
     * @userId
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
     * deleteAll
     */
    void function deleteAll() {
        lock name="#variables._lockName#" type="exclusive" timeout="10" {
            variables.tokens = {};
        }
    }


    /**
     * deleteExpiredBefore
     * Deletes tokens whose expirationDate is before the cutoff.
     *
     * dateCompare() rather than "<": both values are real date objects here, but "<" on dates falls
     * back to string comparison on some engines, and a string comparison of two dates is wrong in
     * ways that only show up at month boundaries.
     *
     * @cutoffDate
     *
     * @return The number of tokens deleted
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
     * count
     * How many tokens are currently held. NOT part of the ITokenStorage contract — a convenience
     * for tests and for looking at the store while developing. Your own provider does not need it.
     */
    numeric function count() {
        lock name="#variables._lockName#" type="readonly" timeout="10" {
            return structCount( variables.tokens );
        }
    }

}
