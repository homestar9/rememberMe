/**
 * Base for integration specs — real SQL Server, real qb, real cookie scope.
 *
 * Two isolation traps this class exists to handle:
 *
 *  1. Every spec in a `?directory=` run shares ONE HTTP request, and therefore ONE cookie scope.
 *     A cookie written by rememberMe() in one spec is still there for the next spec's
 *     cookieExists(). Without resetState(), specs pass alone and fail in a suite.
 *
 *  2. The table is shared state. We DELETE around every spec rather than wrapping in a
 *     transaction: qb manages its own connections and the harness owns the database outright, so
 *     a plain delete is simpler and harder to get subtly wrong.
 *
 * IMPORTANT — how to actually get resetState() to run:
 *
 *     TestBox does NOT invoke a component-level `beforeEach()` method on a BDD bundle. Only the
 *     closures registered with beforeEach()/afterEach() INSIDE a describe() block fire. Declaring
 *     `function beforeEach()` here looks right and silently does nothing. Every BDD bundle that
 *     extends this class must therefore register the closures itself:
 *
 *         describe( "...", function() {
 *             beforeEach( function( currentSpec ) { resetState(); } );
 *             afterEach(  function( currentSpec ) { resetState(); } );
 *             ...
 *         } );
 *
 *     (beforeAll()/afterAll() below ARE bundle lifecycle methods and do fire.)
 */
component extends="coldbox.system.testing.BaseTestCase" {

	this.loadColdBox   = true;
	this.unloadColdBox = false;

	// No `property inject="wirebox"` — spec bundles aren't autowired, and ACF rejects a property
	// declared after this.*. Use BaseTestCase's getWireBox() / getInstance(). See BaseUnitSpec.
	variables.TABLE = "user_remember";

	function beforeAll() {
		// Purge WireBox singletons (and any $property() mocks a previous bundle left on them) so
		// the service under test here is the real, fully-wired one.
		request.coldBoxVirtualApp.restart();
		super.beforeAll();

		// The real singleton, with its real qb / interceptorService / settings injected.
		variables.service = getInstance( "RememberMeService@rememberMe" );
	}

	function afterAll() {
		resetState();
		super.afterAll();
	}

	// --- Isolation --------------------------------------------------------------

	/**
	 * Return the world to a known-empty state: no token rows, no rememberMe cookie.
	 */
	void function resetState() {
		setup();
		truncateTokens();
		clearRememberCookie();
	}

	// --- Helpers ----------------------------------------------------------------

	/**
	 * The name RememberMeService derives at construction: "rememberMe-" & applicationName.
	 */
	string function rememberCookieName() {
		return "rememberMe-" & application.applicationName;
	}

	void function clearRememberCookie() {
		structDelete( cookie, rememberCookieName() );
	}

	void function truncateTokens() {
		queryExecute( "delete from #variables.TABLE#" );
	}

	/**
	 * All rows currently in the table, oldest first. The ORDER BY matters: specs that expect two
	 * rows and reach for [ 1 ] or [ 2 ] need a deterministic order.
	 */
	array function allTokens() {
		return queryExecute(
			"select * from #variables.TABLE# order by id asc",
			[],
			{ returntype : "array" }
		);
	}

	numeric function tokenCount() {
		return queryExecute( "select count(*) as c from #variables.TABLE#" ).c;
	}

	/**
	 * The interceptor registered in config/Coldbox.cfc that records every onRecall announcement.
	 */
	function recallSpy() {
		return getController().getInterceptorService().getInterceptor( "RecallSpy" );
	}

	/**
	 * Writes an arbitrary cookie value directly, bypassing rememberMe(). Used to forge tokens.
	 */
	void function putRememberCookie( required string value ) {
		cookie[ rememberCookieName() ] = arguments.value;
	}

	/**
	 * Encrypts a "selector_validator" pair exactly the way the service does, so specs can forge a
	 * well-formed cookie carrying whatever selector/validator they like.
	 */
	string function forgeToken( required string selector, required string validator ) {
		var settings = getInstance( dsl = "coldbox:modulesettings:rememberMe" );
		return encrypt(
			arguments.selector & "_" & arguments.validator,
			settings.tokenEncryptKey,
			settings.tokenEncryptAlgorithm,
			"Base64"
		);
	}

}
