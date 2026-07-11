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
		days                   : 30
	};

	/**
	 * Purge WireBox singletons (and any $property() mocks left on them) between bundles, so one
	 * bundle's mocking can't bleed into the next.
	 */
	function beforeAll() {
		request.coldBoxVirtualApp.restart();
		super.beforeAll();
	}

	/**
	 * A RememberMeService with its private methods exposed and its settings pinned.
	 *
	 * The component path comes from the WireBox binder rather than being hardcoded — WireBox stays
	 * the source of truth for where the module's service lives.
	 *
	 * Why not getInstance()? RememberMeService@rememberMe is a SINGLETON. Several specs below build
	 * a SECOND service with different settings (a different encryption key, a different hash
	 * algorithm, an empty userServiceClass) and compare its behaviour against the first. Off
	 * getInstance() those are the same object, so $property() on the second silently mutates the
	 * first and the comparison proves nothing. Unit specs need genuinely independent instances.
	 * Integration specs, which want the real wired singleton, use getInstance() — see
	 * BaseIntegrationSpec.
	 */
	function buildService( struct settings = variables.TEST_SETTINGS ) {
		var servicePath = getWireBox()
			.getBinder()
			.getMapping( "RememberMeService@rememberMe" )
			.getPath();

		var service = createMock( servicePath );

		service.$property( "settings", "variables", arguments.settings );
		service.$property( "userServiceClass", "variables", arguments.settings.userServiceClass );

		// Note the intermediate variable: Adobe's parser cannot chain a method off an array
		// LITERAL ( [ "a", "b" ].each( ... ) is "Invalid CFML construct" on ACF, fine on Lucee ).
		var privateMethods = [
			"hashValidator",
			"parseToken",
			"encryptToken",
			"decryptToken",
			"isMatch",
			"getUserService"
		];

		for ( var method in privateMethods ) {
			makePublic( service, method );
		}

		return service;
	}

}
