/**
 * SQLTokenStorage
 *
 * The default token storage provider: plain `queryExecute` against the table named by the `table`
 * setting, on the datasource named by the `datasource` setting ("" = the application default from
 * the host app's Application.cfc).
 *
 * ZERO dependencies — no qb, no ORM, no cbstorages — which is the entire point. rememberMe used to
 * declare `this.dependencies = [ "qb" ]`, and because ColdBox registers a module's own `modules/`
 * folder as real application-wide modules, installing rememberMe forced a qb version into the host
 * app. As of 2.0.0 the module installs nothing, and this provider is why it can still persist
 * tokens out of the box.
 *
 * models/QBTokenStorage.cfc remains in the module as an OPT-IN provider for apps already on qb. The
 * two are behaviourally identical and must stay that way — anything you change here, check there.
 *
 * Satisfies interfaces/ITokenStorage.cfc. It receives only plain values from the service (see the
 * interface) and re-annotates them with cfsqltype for the actual queries — that detail must not
 * leak back across the interface.
 *
 * The SQL is deliberately dialect-neutral ANSI: no TOP/LIMIT, no bracket quoting, no vendor
 * functions. The module documents and tests SQL Server (test-harness/tests/resources/schema.sql),
 * but nothing in here stops these statements running on MySQL, Postgres or Oracle.
 */
component
    hint="I am the default queryExecute-backed token storage for the rememberMe module"
{

    property name="settings" inject="coldbox:modulesettings:rememberMe";


    /**
     * create
     * Persists a new token row. The service supplies every value, dates included.
     *
     * `lastUsedDate` is deliberately ABSENT from the column list — it stays NULL until the token is
     * first recalled (see updateUsage), and it is the schema's only nullable column. `modifiedDate`
     * IS present: it is NOT NULL with no default, and omitting it was a real bug fixed in 1.2.0.
     * `id` is an IDENTITY column and is never supplied.
     *
     * @token { userId, selector, hashedValidator, ipAddress, userAgent, createdDate, modifiedDate, expirationDate }
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
     * getBySelector
     * Returns the token struct for a selector, or an empty struct when there is no match.
     *
     * No TOP/LIMIT on purpose. qb's .first() emitted a grammar-specific "TOP (1)", which would pin
     * this file to SQL Server for no benefit: the selector is a createUuid() and the column is
     * indexed, so the match is already a single-row seek. Taking [ 1 ] in CFML costs nothing and
     * keeps the statement portable — TOP is SQL Server only, LIMIT is not SQL Server, and ANSI
     * FETCH FIRST needs an ORDER BY on SQL Server.
     *
     * `select *` rather than a column list, matching qb's .select(): a host app that has added
     * columns still sees them, so swapping the default provider does not change what callers get.
     *
     * @selector
     */
    struct function getBySelector( required string selector ) {

        // getQueryOptions() hands back a fresh literal every call, so adding a key here is safe.
        var options        = getQueryOptions();
        options.returntype = "array";

        var rows = queryExecute(
            "select * from #getTable()# where selector = :selector",
            { selector: { value: arguments.selector, cfsqltype: "varchar" } },
            options
        );

        // The contract is an EMPTY STRUCT on no match — never null.
        return arrayLen( rows ) ? rows[ 1 ] : {};
    }


    /**
     * updateUsage
     * Stamps the audit columns on a token that was just recalled.
     *
     * @selector
     * @audit { ipAddress, userAgent, lastUsedDate, modifiedDate }
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
     * deleteBySelector
     *
     * @selector
     */
    void function deleteBySelector( required string selector ) {
        queryExecute(
            "delete from #getTable()# where selector = :selector",
            { selector: { value: arguments.selector, cfsqltype: "varchar" } },
            getQueryOptions()
        );
    }


    /**
     * deleteByUserId
     *
     * @userId
     */
    void function deleteByUserId( required numeric userId ) {
        queryExecute(
            "delete from #getTable()# where userId = :userId",
            { userId: { value: arguments.userId, cfsqltype: "integer" } },
            getQueryOptions()
        );
    }


    /**
     * deleteAll
     * An empty ARRAY, not an empty struct, for "no bindings" — queryExecute's own documented
     * default, and the form BaseIntegrationSpec.allTokens() already exercises on all four engines.
     */
    void function deleteAll() {
        queryExecute( "delete from #getTable()#", [], getQueryOptions() );
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

        // Declared BEFORE the call so the read below is safe even on an engine that declines to
        // populate the struct. The name is scoped ("local.") deliberately — an unscoped name
        // resolves to the variables scope on some engines, which would leak between calls.
        var deleteResult = {};

        var options    = getQueryOptions();
        options.result = "local.deleteResult";

        queryExecute(
            "delete from #getTable()# where expirationDate < :cutoffDate",
            { cutoffDate: { value: arguments.cutoffDate, cfsqltype: "timestamp" } },
            options
        );

        // recordCount on a DELETE result is engine-dependent, and the interface allows 0 when the
        // backend cannot report a count. This is the same mechanism qb used internally — its
        // BaseGrammar appends result="local.result" to the options and reads recordCount back off
        // it — and PurgeSpec asserts the exact number on all four engines, so the guard is
        // belt-and-braces rather than a known gap.
        //
        // Do NOT "improve" this into a select count(*) followed by a delete: two statements can
        // disagree if another request inserts a qualifying row between them, and this number is
        // only ever used for logging.
        return structKeyExists( local.deleteResult, "recordCount" ) ? local.deleteResult.recordCount : 0;
    }


    /**
     * getTable
     * The token table name, from settings. Read per call rather than snapshotted in an
     * onDIComplete: unit specs build this component with createMock() + $property(), which skips
     * the WireBox lifecycle entirely, so a snapshot would silently never happen there.
     *
     * The name is interpolated straight into the SQL — an identifier cannot be a bind parameter.
     * It comes from a developer-set module setting, not from user input, so this is not an
     * injection vector in practice; but qb used to pass the name through its grammar's wrapValue()
     * and raw SQL does not, so the allow-list restores that layer and turns a typo into a clear
     * error instead of a baffling SQL syntax failure.
     *
     * The pattern is deliberately BACKSLASH-FREE. Inside a character class a backslash is a literal
     * in Adobe's POSIX engine and an escape in the Java engine Lucee and BoxLang use, so a pattern
     * like [\.\[\]] means different things per engine. Letters, digits, underscores and dots only —
     * enough for "user_remember" and "dbo.user_remember". SQL Server bracket-quoting is not
     * supported and never was: qb would have double-wrapped "[user_remember]" too.
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
     * getQueryOptions
     * The queryExecute options struct passed to every call. An empty struct means the engine uses
     * the application default datasource (the host app's Application.cfc), which is exactly the
     * out-of-the-box behaviour we want.
     *
     * A fresh literal every call, so callers that need an extra key (`returntype`, `result`) can
     * safely mutate what they get back.
     */
    private struct function getQueryOptions() {
        return len( variables.settings.datasource ) ? { datasource: variables.settings.datasource } : {};
    }

}
