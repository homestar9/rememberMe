/**
 * Base for unit specs — no database, no qb, no cookies.
 *
 * Everything here runs against a RememberMeService whose collaborators have been swapped out with
 * $property(), so these specs execute identically on every engine regardless of whether the
 * datasource works.
 */
component extends="coldbox.system.testing.BaseTestCase" {

	this.loadColdBox   = true;
	this.unloadColdBox = false;

	// NOTE: no `property name="wirebox" inject="wirebox"` here. TestBox spec bundles are not
	// autowired by WireBox, so that injection is a silent no-op — and on Adobe it is worse than
	// useless, because ACF requires property declarations to precede any this.* assignment and
	// throws "Property must be defined first within component declaration". BaseTestCase already
	// exposes getWireBox() / getInstance(); those are the WireBox accessors to use.

	// A real AES-256 key. Fixed rather than generated so a failure is reproducible.
	variables.TEST_KEY = "HpNHIyWJc0AYCslJ+W0ye9P6eCxVvv5nQiuoKw99uQc=";

	variables.TEST_SETTINGS = {
		userServiceClass       : "MockUserService",
		tokenEncryptKey        : variables.TEST_KEY,
		tokenEncryptAlgorithm  : "aes",
		validatorHashAlgorithm : "MD5",
		days                   : 30,
		tokenStorageClass      : "QBTokenStorage@rememberMe",
		table                  : "user_remember",
		datasource             : ""
	};

	/**
	 * DO NOT add request.coldBoxVirtualApp.restart() here — it poisons every later bundle in the
	 * same runner request via ColdBox's request-level transient DI cache. Full explanation in
	 * BaseIntegrationSpec.beforeAll(). Nothing needs purging: buildService() below mocks a fresh
	 * createMock() instance, never a WireBox-managed one.
	 */
	function beforeAll() {
		super.beforeAll();
	}

	/**
	 * A RememberMeService with its private methods exposed and its settings pinned.
	 *
	 * The component path comes from the WireBox binder rather than being hardcoded — WireBox stays
	 * the source of truth for where the module's service lives.
	 *
	 * Why not getInstance()? Several specs build a SECOND service with different settings (a
	 * different encryption key, a different hash algorithm, an empty userServiceClass) and compare
	 * its behaviour against the first. createMock() guarantees genuinely independent instances,
	 * independent of WireBox scoping (the mapping is actually NoScope, not a singleton) and of
	 * ColdBox 7's request-level transient DI cache (see AGENTS.md trap 6), and it never touches
	 * the DB-wired dependencies. Integration specs, which want the real wired service, use
	 * getInstance() — see BaseIntegrationSpec.
	 */
	function buildService( struct settings = variables.TEST_SETTINGS ) {
		var servicePath = getWireBox()
			.getBinder()
			.getMapping( "RememberMeService@rememberMe" )
			.getPath();

		var service = createMock( servicePath );

		service.$property( "settings", "variables", arguments.settings );
		service.$property( "userServiceClass", "variables", arguments.settings.userServiceClass );
		service.$property( "tokenStorageClass", "variables", arguments.settings.tokenStorageClass );

		// Note the intermediate variable: Adobe's parser cannot chain a method off an array
		// LITERAL ( [ "a", "b" ].each( ... ) is "Invalid CFML construct" on ACF, fine on Lucee ).
		var privateMethods = [
			"hashValidator",
			"parseToken",
			"encryptToken",
			"decryptToken",
			"isMatch",
			"getUserService",
			"getTokenStorage"
		];

		for ( var method in privateMethods ) {
			makePublic( service, method );
		}

		return service;
	}

}
