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
	// Pre-boot default only — beforeAll() re-derives this from the module's `table` setting.
	variables.TABLE = "user_remember";

	/**
	 * DO NOT add request.coldBoxVirtualApp.restart() here.
	 *
	 * It looks like good hygiene — a fresh WireBox per bundle — and it is actively harmful. Every
	 * bundle in a `?directory=` run shares ONE request, and ColdBox 7's WireBox memoises each
	 * transient's resolved dependencies for the request in `request.cbTransientDICache`. Restart
	 * mid-request and the cache still holds the PREVIOUS boot's (now shut-down) interceptorService /
	 * wirebox / cachebox, which WireBox then injects into every transient it rebuilds. The service
	 * ends up announcing onRecall into a dead InterceptorService that no registered interceptor
	 * listens to, and ColdBoxScheduledTask ends up with an empty CacheFactory. Both symptoms appear
	 * ONLY from the second bundle onward, so every bundle passes when run alone.
	 *
	 * There is nothing to purge anyway: RememberMeService@rememberMe is NoScope (a transient — see
	 * ModuleConfig.onLoad), and BaseUnitSpec mocks via createMock() on a fresh instance, never on a
	 * WireBox-managed one. The VirtualApp that Application.cfc boots per request is all the
	 * isolation this suite needs; per-spec request state is handled by resetState() -> setup().
	 */
	function beforeAll() {
		super.beforeAll();

		// The real, fully-wired service.
		variables.service = getInstance( "RememberMeService@rememberMe" );

		// The table the default storage actually uses — one source of truth, no hardcode drift.
		variables.TABLE = getInstance( dsl = "coldbox:modulesettings:rememberMe" ).table;
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
