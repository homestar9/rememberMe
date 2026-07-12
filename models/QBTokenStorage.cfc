/**
 * QBTokenStorage
 *
 * The default token storage provider: raw qb against the table named by the `table` setting,
 * on the datasource named by the `datasource` setting ("" = the application default from the
 * host app's Application.cfc). Satisfies interfaces/ITokenStorage.cfc and is the reference
 * implementation for anyone writing a custom provider.
 *
 * It receives only plain values from the service (see the interface) and re-annotates them with
 * cfsqltype for the actual queries — that detail must not leak back across the interface.
 */
component
    hint="I am the default qb-backed token storage for the rememberMe module"
{

    property name="qb" inject="provider:QueryBuilder@qb";
    property name="settings" inject="coldbox:modulesettings:rememberMe";


    /**
     * create
     * Persists a new token row. The service supplies every value, dates included.
     *
     * @token { userId, selector, hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, expirationDate }
     */
    void function create( required struct token ) {
        qb.from( getTable() )
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
     * getBySelector
     * Returns the token struct for a selector, or an empty struct when there is no match.
     *
     * @selector
     */
    struct function getBySelector( required string selector ) {
        return qb
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
     * updateUsage
     * Stamps the audit columns on a token that was just recalled.
     *
     * @selector
     * @audit { ipAddress, userAgent, lastUsedDate, modifiedDate }
     */
    void function updateUsage( required string selector, required struct audit ) {
        qb.from( getTable() )
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
     * deleteBySelector
     *
     * @selector
     */
    void function deleteBySelector( required string selector ) {
        // options is delete()'s THIRD positional parameter ( id, idColumnName, options ) — it must
        // be passed by name here or it would be treated as an id to delete by.
        qb.from( getTable() )
            .where( "selector", arguments.selector )
            .delete( options = getQueryOptions() );
    }


    /**
     * deleteByUserId
     *
     * @userId
     */
    void function deleteByUserId( required numeric userId ) {
        qb.from( getTable() )
            .where( "userId", arguments.userId )
            .delete( options = getQueryOptions() );
    }


    /**
     * deleteAll
     */
    void function deleteAll() {
        qb.from( getTable() ).delete( options = getQueryOptions() );
    }


    /**
     * deleteExpiredBefore
     * Deletes rows whose expirationDate is before the cutoff.
     *
     * @cutoffDate
     *
     * @return The number of rows deleted
     */
    numeric function deleteExpiredBefore( required date cutoffDate ) {

        var response = qb.from( getTable() )
            .where( "expirationDate", "<", {
                value = arguments.cutoffDate,
                cfsqltype = "timestamp"
            } )
            .delete( options = getQueryOptions() );

        // recordCount on a DELETE result is engine-dependent
        return structKeyExists( response.result, "recordCount" ) ? response.result.recordCount : 0;
    }


    /**
     * getTable
     * The token table name, from settings. Read per call rather than snapshotted in an
     * onDIComplete: unit specs build this component with createMock() + $property(), which skips
     * the WireBox lifecycle entirely, so a snapshot would silently never happen there.
     */
    private string function getTable() {
        return variables.settings.table;
    }


    /**
     * getQueryOptions
     * The queryExecute options passed to every terminal qb call. An empty struct means the engine
     * uses the application default datasource (the host app's Application.cfc), which is exactly
     * the out-of-the-box behaviour we want.
     */
    private struct function getQueryOptions() {
        return len( variables.settings.datasource ) ? { datasource: variables.settings.datasource } : {};
    }

}
