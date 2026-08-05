/**
 * Integration specs for the storage abstraction itself:
 *
 *  - the full lifecycle running against a CUSTOM, in-memory provider that lives OUTSIDE the module
 *    (test-harness/models/StubTokenStorage.cfc), proving the tokenStorageClass seam works
 *    end-to-end for a host-app class — nothing may touch SQL;
 *  - the datasource option on both SQL-backed providers, proving the per-query options plumbing
 *    reaches the engine without touching config/Datasource.cfm.
 *
 * StubTokenStorage stays in the harness even though the module now ships its own
 * MemoryTokenStorage. It is the only thing here proving a class outside the module can satisfy the
 * contract, which is exactly what the "write your own provider" documentation promises.
 *
 * The tokenStorageClass override happens per spec on a private service instance — NEVER in the
 * harness config, which would silently swap the storage under every other integration bundle.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	function run() {

		describe( "Custom token storage providers", function() {

			beforeEach( function( currentSpec ) {
				resetState();
				recallSpy().reset();
				getInstance( "StubTokenStorage" ).clear();
			} );

			afterEach( function( currentSpec ) {
				resetState();
				getInstance( "StubTokenStorage" ).clear();
			} );

			describe( "the full lifecycle against an in-memory provider", function() {

				it( "remembers, recalls and forgets without ever touching the database", function() {
					// StubTokenStorage is a singleton, so this is the same instance the service
					// will resolve — the spec can watch its state from the outside.
					var stub = getInstance( "StubTokenStorage" );

					// A real wired service, re-pointed at the stub by NAME so the spec proves the
					// whole WireBox-resolution path a host app would use.
					var svc = prepareMock( getInstance( "RememberMeService@rememberMe" ) );
					svc.$property( "tokenStorageClass", "variables", "StubTokenStorage" );

					svc.rememberMe( 7 );
					expect( stub.count() ).toBe( 1 );
					expect( tokenCount() ).toBe( 0, "SQL must be untouched — the provider owns persistence" );
					expect( svc.cookieExists() ).toBeTrue();

					var user = svc.recallMe();
					expect( user.getId() ).toBe( 7 );
					expect( user.isLoaded() ).toBeTrue();

					svc.forgetMe();
					expect( stub.count() ).toBe( 0 );
					expect( svc.cookieExists() ).toBeFalse();
				} );

				it( "rejects a forged validator through a custom provider too", function() {
					// The hash-asymmetry check lives in the SERVICE, so no provider can lose it.
					var svc = prepareMock( getInstance( "RememberMeService@rememberMe" ) );
					svc.$property( "tokenStorageClass", "variables", "StubTokenStorage" );

					svc.rememberMe( 1 );

					// Fetch the real selector out of the cookie the service just wrote.
					var settings     = getInstance( dsl = "coldbox:modulesettings:rememberMe" );
					var plaintext    = decrypt( svc.getCookie(), settings.tokenEncryptKey, settings.tokenEncryptAlgorithm, "Base64" );
					var selector     = plaintext.listGetAt( 1, "_" );

					putRememberCookie( forgeToken( selector, createUuid() ) );

					expect( function() {
						svc.recallMe();
					} ).toThrow( type = "InvalidToken" );
				} );

				it( "purgeExpired() delegates to the provider and returns its count", function() {
					var stub = getInstance( "StubTokenStorage" );
					var svc  = prepareMock( getInstance( "RememberMeService@rememberMe" ) );
					svc.$property( "tokenStorageClass", "variables", "StubTokenStorage" );

					// One live token, one long-expired token planted directly in the provider.
					svc.rememberMe( 1 );
					stub.create( {
						userId          : 2,
						selector        : createUuid(),
						hashedValidator : hash( createUuid(), "MD5" ),
						ipAddress       : "127.0.0.1",
						userAgent       : "spec",
						createdDate     : dateAdd( "d", -90, now() ),
						modifiedDate    : dateAdd( "d", -90, now() ),
						expirationDate  : dateAdd( "d", -60, now() )
					} );

					expect( svc.purgeExpired() ).toBe( 1 );
					expect( stub.count() ).toBe( 1, "the live token must survive the purge" );
				} );

			} );

			describe( "the datasource option on the SQL-backed providers", function() {

				it( "reaches the engine from SQLTokenStorage — a real named datasource works, a bogus one throws", function() {
					// SQLTokenStorage is the DEFAULT provider, so this is the plumbing that matters
					// to almost every host app.
					expectDatasourceOptionToReachTheEngine( "SQLTokenStorage@rememberMe" );
				} );

				it( "reaches the engine from QBTokenStorage too", function() {
					// The opt-in provider. qb is a HARNESS dependency now, not the module's — this
					// spec is the reason the harness installs it at all.
					expectDatasourceOptionToReachTheEngine( "QBTokenStorage@rememberMe" );
				} );

			} );

			describe( "the table setting on the default provider", function() {

				it( "is validated, because a table name cannot be a bind parameter", function() {
					// qb passed the table name through its grammar's wrapValue(). Raw SQL does not,
					// so SQLTokenStorage keeps an allow-list in its place.
					var settings = getInstance( dsl = "coldbox:modulesettings:rememberMe" );
					var storage  = prepareMock( getInstance( "SQLTokenStorage@rememberMe" ) );
					storage.$property( "settings", "variables", {
						table      : "user_remember; drop table user_remember--",
						datasource : settings.datasource
					} );

					expect( function() {
						storage.getBySelector( createUuid() );
					} ).toThrow( type = "InvalidConfiguration" );

					// And the real table is still there.
					expect( tokenCount() ).toBe( 0 );
					expect( allTokens() ).toBeArray();
				} );

			} );

		} );

	}

	/**
	 * Drives one provider's `datasource` setting both ways: the harness's own datasource named
	 * EXPLICITLY must work, and a datasource that does not exist must fail loudly. The second half
	 * is the real assertion — it proves the option is actually reaching queryExecute rather than
	 * being silently dropped and falling back to the application default.
	 *
	 * @storageDSL WireBox DSL of the provider to exercise
	 */
	private void function expectDatasourceOptionToReachTheEngine( required string storageDSL ) {

		var settings = getInstance( dsl = "coldbox:modulesettings:rememberMe" );

		var named = prepareMock( getInstance( arguments.storageDSL ) );
		named.$property( "settings", "variables", {
			table      : settings.table,
			datasource : getApplicationMetadata().datasource
		} );
		expect( named.getBySelector( createUuid() ) ).toBeEmpty();

		var bogus = prepareMock( getInstance( arguments.storageDSL ) );
		bogus.$property( "settings", "variables", {
			table      : settings.table,
			datasource : "rememberme-no-such-datasource"
		} );
		expect( function() {
			bogus.getBySelector( createUuid() );
		} ).toThrow();
	}

}
