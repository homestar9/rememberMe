/**
 * Stores remember-me tokens in a database with qb.
 *
 * A storage provider saves, loads, updates, and deletes token records for RememberMeService. This
 * provider is optional. The rememberMe module does not install qb. To use this provider, run
 * `box install qb` in the host application and set tokenStorageClass to `QBTokenStorage@rememberMe`.
 *
 * The table setting selects the token table. The datasource setting selects the datasource. An
 * empty datasource setting uses the application's default datasource.
 *
 * This provider follows ITokenStorage.cfc. The service passes plain CFML values and an already
 * hashed validator. This provider adds cfsqltype values when it builds a database query. Each
 * cfsqltype value tells the database what type of value it will receive.
 *
 * Keep this provider's behavior aligned with SQLTokenStorage.
 */
component
    hint="I am the opt-in qb-backed token storage for the rememberMe module. Requires qb, which the module does not install."
{

    property name="wirebox" inject="wirebox";
    property name="settings" inject="coldbox:modulesettings:rememberMe";


    /**
     * Inserts a new token record.
     *
     * The service supplies every value, including the dates.
     *
     * @token The complete token struct to insert. It must contain userId, selector,
     *        hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, and expirationDate.
     */
    void function create( required struct token ) {
        getQB()
            .from( getTable() )
            .insert(
                values = {
                    userId: arguments.token.userId,
                    selector: arguments.token.selector,
                    hashedValidator: arguments.token.hashedValidator,
                    ipAddress = { value = arguments.token.ipAddress, cfsqltype = "varchar" },
                    userAgent = { value = arguments.token.userAgent, cfsqltype = "varchar" },
                    createdDate = { value = arguments.token.createdDate, cfsqltype = "timestamp" },
                    modifiedDate = { value = arguments.token.modifiedDate, cfsqltype = "timestamp" },
                    expirationDate = { value = arguments.token.expirationDate, cfsqltype = "timestamp" }
                },
                options = getQueryOptions()
            )
        ;
    }


    /**
     * Returns the token record with the given selector.
     *
     * @selector The unique value used to find a stored token.
     * @return The stored token, or an empty struct when no token matches.
     */
    struct function getBySelector( required string selector ) {
        return getQB()
            .select()
            .from( getTable() )
            .where( "selector", "=", {
                value = arguments.selector,
                cfsqltype = "varchar"
            } )
            .first( getQueryOptions() )
        ;
    }


    /**
     * Updates the audit fields after a successful token recall.
     *
     * Audit fields describe the request that used the token and the time of that use.
     *
     * @selector The unique value used to find the stored token.
     * @audit A struct containing ipAddress, userAgent, lastUsedDate, and modifiedDate.
     */
    void function updateUsage( required string selector, required struct audit ) {
        getQB()
            .from( getTable() )
            .where( "selector", "=", { value = arguments.selector, cfsqltype = "varchar" } )
            .update(
                values = {
                    ipAddress = { value = arguments.audit.ipAddress, cfsqltype = "varchar" },
                    userAgent = { value = arguments.audit.userAgent, cfsqltype = "varchar" },
                    lastUsedDate = { value = arguments.audit.lastUsedDate, cfsqltype = "timestamp" },
                    modifiedDate = { value = arguments.audit.modifiedDate, cfsqltype = "timestamp" }
                },
                options = getQueryOptions()
            )
        ;
    }


    /**
     * Deletes the token record with the given selector.
     *
     * @selector The unique value used to find the stored token.
     */
    void function deleteBySelector( required string selector ) {
        // qb defines options as the third argument to delete(). Pass options by name so qb does not
        // treat the options struct as a record ID.
        getQB()
            .from( getTable() )
            .where( "selector", arguments.selector )
            .delete( options = getQueryOptions() );
    }


    /**
     * Deletes every token record for one user.
     *
     * @userId The ID of the user whose tokens will be deleted.
     */
    void function deleteByUserId( required numeric userId ) {
        getQB()
            .from( getTable() )
            .where( "userId", arguments.userId )
            .delete( options = getQueryOptions() );
    }


    /**
     * Deletes every token record.
     */
    void function deleteAll() {
        getQB().from( getTable() ).delete( options = getQueryOptions() );
    }


    /**
     * Deletes token records that expired before the cutoff date.
     *
     * @cutoffDate Delete records with an expirationDate before this date.
     * @return The number of deleted records, or 0 when the engine does not report a count.
     */
    numeric function deleteExpiredBefore( required date cutoffDate ) {

        var response = getQB()
            .from( getTable() )
            .where( "expirationDate", "<", {
                value = arguments.cutoffDate,
                cfsqltype = "timestamp"
            } )
            .delete( options = getQueryOptions() );

        // Some engines do not include recordCount after a DELETE. Return 0 when no count is
        // available, as allowed by ITokenStorage.
        return structKeyExists( response.result, "recordCount" ) ? response.result.recordCount : 0;
    }


    /**
     * Returns a qb QueryBuilder instance.
     *
     * WireBox resolves qb only on the first call. This provider reuses that QueryBuilder on later
     * calls. Delayed loading lets ColdBox register this provider when qb is not installed. An
     * application only needs qb when the application selects QBTokenStorage.
     *
     * @return The qb QueryBuilder instance.
     * @throws MissingDependency When WireBox cannot find qb.
     */
    private any function getQB() {
        if ( !structKeyExists( variables, "qb" ) ) {
            try {
                variables.qb = variables.wirebox.getInstance( "QueryBuilder@qb" );
            } catch ( any e ) {
                throw(
                    type = "MissingDependency",
                    message = "QBTokenStorage needs qb, which rememberMe does not install as of 2.0.0. Run `box install qb` in your app, or set `moduleSettings.rememberMe.tokenStorageClass` to `SQLTokenStorage@rememberMe` to use the built-in provider, which needs no dependencies.",
                    detail = "WireBox could not resolve [QueryBuilder@qb]: #e.message#"
                );
            }
        }

        return variables.qb;
    }


    /**
     * Returns the token table name from the module settings.
     *
     * Read the setting on every call instead of caching it. This keeps the value current when a
     * caller replaces the settings after creating the component.
     *
     * @return The configured table name.
     */
    private string function getTable() {
        return variables.settings.table;
    }


    /**
     * Returns the query options for the configured datasource.
     *
     * An empty struct tells qb to use the application's default datasource.
     *
     * @return A new query options struct.
     */
    private struct function getQueryOptions() {
        return len( variables.settings.datasource ) ? { datasource: variables.settings.datasource } : {};
    }

}
