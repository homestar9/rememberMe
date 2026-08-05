/**
 * QBTokenStorage
 *
 * An OPT-IN token storage provider: raw qb against the table named by the `table` setting, on the
 * datasource named by the `datasource` setting ("" = the application default from the host app's
 * Application.cfc). Satisfies interfaces/ITokenStorage.cfc.
 *
 * This is not the default and rememberMe does NOT install qb. Up to 1.4.0 it declared
 * `this.dependencies = [ "qb" ]` and shipped qb inside its own modules/ folder, which ColdBox then
 * registered as a real application-wide module — so installing rememberMe forced a qb version onto
 * the host app. 2.0.0 stopped doing that. The default is now models/SQLTokenStorage.cfc, which
 * needs nothing. To use this one instead:
 *
 *     box install qb
 *
 * and set `moduleSettings.rememberMe.tokenStorageClass = "QBTokenStorage@rememberMe"`.
 *
 * It receives only plain values from the service (see the interface) and re-annotates them with
 * cfsqltype for the actual queries — that detail must not leak back across the interface.
 *
 * SQLTokenStorage is behaviourally identical to this file. Anything you change here, check there.
 */
component
    hint="I am the opt-in qb-backed token storage for the rememberMe module. Requires qb, which the module does not install."
{

    property name="wirebox" inject="wirebox";
    property name="settings" inject="coldbox:modulesettings:rememberMe";


    /**
     * create
     * Persists a new token row. The service supplies every value, dates included.
     *
     * @token { userId, selector, hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, expirationDate }
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
     * getBySelector
     * Returns the token struct for a selector, or an empty struct when there is no match.
     *
     * @selector
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
     * updateUsage
     * Stamps the audit columns on a token that was just recalled.
     *
     * @selector
     * @audit { ipAddress, userAgent, lastUsedDate, modifiedDate }
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
     * deleteBySelector
     *
     * @selector
     */
    void function deleteBySelector( required string selector ) {
        // options is delete()'s THIRD positional parameter ( id, idColumnName, options ) — it must
        // be passed by name here or it would be treated as an id to delete by.
        getQB()
            .from( getTable() )
            .where( "selector", arguments.selector )
            .delete( options = getQueryOptions() );
    }


    /**
     * deleteByUserId
     *
     * @userId
     */
    void function deleteByUserId( required numeric userId ) {
        getQB()
            .from( getTable() )
            .where( "userId", arguments.userId )
            .delete( options = getQueryOptions() );
    }


    /**
     * deleteAll
     */
    void function deleteAll() {
        getQB().from( getTable() ).delete( options = getQueryOptions() );
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

        var response = getQB()
            .from( getTable() )
            .where( "expirationDate", "<", {
                value = arguments.cutoffDate,
                cfsqltype = "timestamp"
            } )
            .delete( options = getQueryOptions() );

        // recordCount on a DELETE result is engine-dependent
        return structKeyExists( response.result, "recordCount" ) ? response.result.recordCount : 0;
    }


    /**
     * getQB
     * Resolves a QueryBuilder, lazily and memoised — the same shape as
     * RememberMeService.getUserService() / getTokenStorage().
     *
     * Lazily, and NOT as a `property name="qb" inject="provider:QueryBuilder@qb"`, for one specific
     * reason: rememberMe no longer installs qb, so on most host apps `QueryBuilder@qb` does not
     * exist. A build-time injection would make this component impossible to construct there, which
     * in turn would break the WireBox mapping in ModuleConfig.onLoad() and the unit specs that
     * build it with createMock(). Resolving here means the file is completely inert until someone
     * actually configures it, and the failure — when it comes — says what to do about it.
     *
     * @throws MissingDependency
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
