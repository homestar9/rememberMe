/**
 * Integration specs for the storage abstraction itself:
 *
 *  - the full lifecycle running against a CUSTOM (non-qb, in-memory) provider, proving the
 *    tokenStorageClass seam actually works end-to-end — nothing may touch SQL;
 *  - the default QBTokenStorage's datasource option, proving the per-query options plumbing
 *    reaches the engine without touching config/Datasource.cfm.
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

			describe( "QBTokenStorage's datasource option", function() {

				it( "reaches the engine when set — a real named datasource works, a bogus one throws", function() {
					var storagePath = getWireBox()
						.getBinder()
						.getMapping( "QBTokenStorage@rememberMe" )
						.getPath();
					var settings = getInstance( dsl = "coldbox:modulesettings:rememberMe" );

					// The harness's own datasource, but named EXPLICITLY instead of defaulted.
					var named = prepareMock( getInstance( "QBTokenStorage@rememberMe" ) );
					named.$property( "settings", "variables", {
						table      : settings.table,
						datasource : getApplicationMetadata().datasource
					} );
					expect( named.getBySelector( createUuid() ) ).toBeEmpty();

					// A datasource that does not exist must fail loudly, proving the option is
					// actually reaching queryExecute and not being silently dropped.
					var bogus = prepareMock( getInstance( "QBTokenStorage@rememberMe" ) );
					bogus.$property( "settings", "variables", {
						table      : settings.table,
						datasource : "rememberme-no-such-datasource"
					} );
					expect( function() {
						bogus.getBySelector( createUuid() );
					} ).toThrow();
				} );

			} );

		} );

	}

}
