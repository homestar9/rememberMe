/**
 * Stores remember-me tokens in a database with queryExecute().
 *
 * A storage provider saves, loads, updates, and deletes token records for RememberMeService. This
 * is the default provider. The table setting selects the token table. The datasource setting
 * selects the datasource. An empty datasource setting uses the application's default datasource.
 *
 * This provider has no third-party dependencies. queryExecute() is built into CFML.
 *
 * This provider follows ITokenStorage.cfc. The service passes plain CFML values and an already
 * hashed validator. This provider adds cfsqltype values when it builds a database query. Each
 * cfsqltype value tells the database what type of value it will receive.
 *
 * The SQL avoids database-specific features such as TOP, LIMIT, bracket quoting, and vendor
 * functions. The project tests SQL Server. The statements also use standard SQL where possible.
 *
 * Keep this provider's behavior aligned with QBTokenStorage.
 */
component
    hint="I am the default queryExecute-backed token storage for the rememberMe module"
{

    property name="settings" inject="coldbox:modulesettings:rememberMe";


    /**
     * Inserts a new token record.
     *
     * The service supplies every value, including the dates. lastUsedDate stays null until the
     * first successful recall. The database creates the id value because id is an identity column.
     * modifiedDate is required because the table has no default value for that column.
     *
     * Named query parameters keep each value matched to its column. This prevents values from
     * shifting to the wrong columns when the insert changes.
     *
     * @token The complete token struct to insert. It must contain userId, selector,
     *        hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, and expirationDate.
     */
    void function create( required struct token ) {
        queryExecute(
            "insert into #getTable()#
                    ( userId, selector, hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, expirationDate )
                values
                    ( :userId, :selector, :hashedValidator, :ipAddress, :userAgent, :createdDate, :modifiedDate, :expirationDate )",
            {
                userId: { value: arguments.token.userId, cfsqltype: "integer" },
                selector: { value: arguments.token.selector, cfsqltype: "varchar" },
                hashedValidator: { value: arguments.token.hashedValidator, cfsqltype: "varchar" },
                ipAddress: { value: arguments.token.ipAddress, cfsqltype: "varchar" },
                userAgent: { value: arguments.token.userAgent, cfsqltype: "varchar" },
                createdDate: { value: arguments.token.createdDate, cfsqltype: "timestamp" },
                modifiedDate: { value: arguments.token.modifiedDate, cfsqltype: "timestamp" },
                expirationDate: { value: arguments.token.expirationDate, cfsqltype: "timestamp" }
            },
            getQueryOptions()
        );
    }


    /**
     * Returns the token record with the given selector.
     *
     * The query does not use TOP or LIMIT because those clauses do not work across all database
     * systems. A selector is a unique identifier, also called a UUID. The selector is stored in an
     * indexed column, so the query should match one record. CFML returns the first record from the
     * result array.
     *
     * The query selects every column to match QBTokenStorage. This also returns custom columns that
     * a host application added to the token table.
     *
     * @selector The unique value used to find a stored token.
     * @return The stored token, or an empty struct when no token matches.
     */
    struct function getBySelector( required string selector ) {

        // getQueryOptions() returns a new struct, so this change affects only the current query.
        var options        = getQueryOptions();
        options.returntype = "array";

        var rows = queryExecute(
            "select * from #getTable()# where selector = :selector",
            { selector: { value: arguments.selector, cfsqltype: "varchar" } },
            options
        );

        // ITokenStorage requires an empty struct when no token matches.
        return arrayLen( rows ) ? rows[ 1 ] : {};
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
        queryExecute(
            "update #getTable()#
                    set ipAddress    = :ipAddress,
                        userAgent    = :userAgent,
                        lastUsedDate = :lastUsedDate,
                        modifiedDate = :modifiedDate
                where selector = :selector",
            {
                ipAddress: { value: arguments.audit.ipAddress, cfsqltype: "varchar" },
                userAgent: { value: arguments.audit.userAgent, cfsqltype: "varchar" },
                lastUsedDate: { value: arguments.audit.lastUsedDate, cfsqltype: "timestamp" },
                modifiedDate: { value: arguments.audit.modifiedDate, cfsqltype: "timestamp" },
                selector: { value: arguments.selector, cfsqltype: "varchar" }
            },
            getQueryOptions()
        );
    }


    /**
     * Deletes the token record with the given selector.
     *
     * @selector The unique value used to find the stored token.
     */
    void function deleteBySelector( required string selector ) {
        queryExecute(
            "delete from #getTable()# where selector = :selector",
            { selector: { value: arguments.selector, cfsqltype: "varchar" } },
            getQueryOptions()
        );
    }


    /**
     * Deletes every token record for one user.
     *
     * @userId The ID of the user whose tokens will be deleted.
     */
    void function deleteByUserId( required numeric userId ) {
        queryExecute(
            "delete from #getTable()# where userId = :userId",
            { userId: { value: arguments.userId, cfsqltype: "integer" } },
            getQueryOptions()
        );
    }


    /**
     * Deletes every token record.
     *
     * Pass an empty array for the parameter bindings. An empty array is the documented
     * queryExecute() value for a query with no bindings and works across the supported engines.
     */
    void function deleteAll() {
        queryExecute( "delete from #getTable()#", [], getQueryOptions() );
    }


    /**
     * Deletes token records that expired before the cutoff date.
     *
     * @cutoffDate Delete records with an expirationDate before this date.
     * @return The number of deleted records, or 0 when the engine does not report a count.
     */
    numeric function deleteExpiredBefore( required date cutoffDate ) {

        // Create the result struct before the query because some engines may not create it. The
        // local scope also prevents one call from leaving result data for a later call.
        var deleteResult = {};

        var options    = getQueryOptions();
        options.result = "local.deleteResult";

        queryExecute(
            "delete from #getTable()# where expirationDate < :cutoffDate",
            { cutoffDate: { value: arguments.cutoffDate, cfsqltype: "timestamp" } },
            options
        );

        // Some engines do not include recordCount after a DELETE. Return 0 when no count is
        // available, as allowed by ITokenStorage.
        //
        // Do not count with one query and delete with another query. Another request could change
        // the matching rows between those queries and make the count incorrect.
        return structKeyExists( local.deleteResult, "recordCount" ) ? local.deleteResult.recordCount : 0;
    }


    /**
     * Returns a safe token table name from the module settings.
     *
     * Read the setting on every call instead of caching it. This keeps the value current when a
     * caller replaces the settings after creating the component.
     *
     * A table name is inserted directly into SQL because SQL identifiers cannot use query
     * parameters. An allow-list accepts only known-safe characters. This allow-list also gives a
     * clear configuration error. Valid names may contain letters, numbers, underscores, and dots.
     *
     * The regular expression has no backslashes because Adobe ColdFusion and the Java-based CFML
     * engines handle backslashes differently inside a character group. Bracket-quoted table names
     * are not supported.
     *
     * @return The validated table name.
     * @throws InvalidConfiguration When the table name contains an unsupported character.
     */
    private string function getTable() {

        var table = variables.settings.table;

        if ( !reFind( "^[A-Za-z0-9_.]+$", table ) ) {
            throw(
                type = "InvalidConfiguration",
                message = "Invalid [table] setting [#table#]. The rememberMe token table name is interpolated into SQL (an identifier cannot be a bind parameter), so it may contain letters, numbers, underscores and dots only."
            );
        }

        return table;
    }


    /**
     * Returns the queryExecute() options for the configured datasource.
     *
     * An empty struct tells the engine to use the application's default datasource. The function
     * returns a new struct on every call. A caller can add options such as returntype or result
     * without changing the options for another query.
     *
     * @return A new query options struct.
     */
    private struct function getQueryOptions() {
        return len( variables.settings.datasource ) ? { datasource: variables.settings.datasource } : {};
    }

}
