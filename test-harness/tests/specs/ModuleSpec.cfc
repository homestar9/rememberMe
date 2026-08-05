/**
 * Sanity: does the module load at all, and is its public surface wired up?
 * If this bundle is red, nothing else in the suite means anything.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run() {

		describe( "The rememberMe module", function() {

			it( "is registered with ColdBox", function() {
				var modules = getController().getModuleService().getModuleRegistry();
				expect( modules ).toHaveKey( "rememberMe" );
			} );

			it( "maps RememberMeService@rememberMe into WireBox", function() {
				var service = getInstance( "RememberMeService@rememberMe" );
				expect( service ).toBeComponent();
				expect( getMetadata( service ).name ).toInclude( "RememberMeService" );
			} );

			it( "maps SQLTokenStorage@rememberMe into WireBox", function() {
				var storage = getInstance( "SQLTokenStorage@rememberMe" );
				expect( storage ).toBeComponent();
				expect( getMetadata( storage ).name ).toInclude( "SQLTokenStorage" );
			} );

			it( "maps MemoryTokenStorage@rememberMe into WireBox", function() {
				var storage = getInstance( "MemoryTokenStorage@rememberMe" );
				expect( storage ).toBeComponent();
				expect( getMetadata( storage ).name ).toInclude( "MemoryTokenStorage" );
			} );

			it( "maps MemoryTokenStorage as a SINGLETON, or it could never recall anything", function() {
				// Every other mapping in this module is a transient. This one must not be: a fresh
				// in-memory store per injection would start empty every time. Proven behaviourally
				// rather than by identity comparison — write through one handle, read through the
				// other.
				var writer = getInstance( "MemoryTokenStorage@rememberMe" );
				var reader = getInstance( "MemoryTokenStorage@rememberMe" );

				writer.deleteAll();
				writer.create( {
					userId : 1,
					selector : createUuid(),
					hashedValidator : "abc",
					ipAddress : "127.0.0.1",
					userAgent : "spec",
					createdDate : now(),
					modifiedDate : now(),
					expirationDate : dateAdd( "d", 1, now() )
				} );

				expect( reader.count() ).toBe( 1, "Two getInstance() calls must return the same store" );

				// It is a singleton and this is a shared application — do not leave a token behind.
				writer.deleteAll();
			} );

			it( "maps QBTokenStorage@rememberMe into WireBox even though qb is opt-in", function() {
				// The mapping is declared unconditionally. It resolves without qb because
				// QBTokenStorage looks qb up lazily in getQB() instead of injecting it at build
				// time — so a host app without qb can still boot the module.
				var storage = getInstance( "QBTokenStorage@rememberMe" );
				expect( storage ).toBeComponent();
				expect( getMetadata( storage ).name ).toInclude( "QBTokenStorage" );
			} );

			it( "declares its documented settings", function() {
				var settings = getInstance( dsl = "coldbox:modulesettings:rememberMe" );

				expect( settings ).toHaveKey( "userServiceClass" );
				expect( settings ).toHaveKey( "tokenEncryptKey" );
				expect( settings ).toHaveKey( "tokenEncryptAlgorithm" );
				expect( settings ).toHaveKey( "validatorHashAlgorithm" );
				expect( settings ).toHaveKey( "days" );
				expect( settings ).toHaveKey( "autoPurge" );
				expect( settings ).toHaveKey( "purgeGraceDays" );
				expect( settings ).toHaveKey( "purgeTime" );
				expect( settings ).toHaveKey( "tokenStorageClass" );
				expect( settings ).toHaveKey( "table" );
				expect( settings ).toHaveKey( "datasource" );

				// The harness overrides these; the defaults themselves live in ModuleConfig.cfc
				expect( settings.tokenEncryptAlgorithm ).toBe( "aes" );
				expect( settings.validatorHashAlgorithm ).toBe( "MD5" );
				expect( settings.days ).toBe( 30 );

				// The harness does not override the purge settings, so these ARE the module defaults
				expect( settings.autoPurge ).toBeTrue();
				expect( settings.purgeGraceDays ).toBe( 1 );
				expect( settings.purgeTime ).toBe( "04:00" );

				// Nor the storage settings — these are the module defaults too
				expect( settings.tokenStorageClass ).toBe( "SQLTokenStorage@rememberMe" );
				expect( settings.table ).toBe( "user_remember" );
				expect( settings.datasource ).toBe( "" );
			} );

			it( "registers its scheduler", function() {
				expect(
					getController().getSchedulerService().hasScheduler( "cbScheduler@rememberMe" )
				).toBeTrue();
			} );

			it( "registers the purge task on its scheduler", function() {
				var scheduler = getController().getSchedulerService().getSchedulers()[ "cbScheduler@rememberMe" ];
				expect( scheduler.hasTask( "rememberMe-purge-expired-tokens" ) ).toBeTrue();
			} );

			it( "registers the onRecall custom interception point", function() {
				var points = getController().getInterceptorService().getInterceptionPoints();
				expect( points ).toInclude( "onRecall" );
			} );

			it( "declares NO module dependencies", function() {
				// The headline of 2.0.0. ColdBox registers a module's own modules/ folder as real
				// application-wide modules, so any dependency declared here is forced onto every
				// host app. Up to 1.4.0 this array held "qb". It must stay empty.
				var registeredModules = getController().getSetting( "modules" );
				expect( registeredModules ).toHaveKey( "rememberMe" );
				expect( registeredModules.rememberMe.dependencies ).toBeEmpty();
			} );

			it( "wires its default storage provider with nothing but the module settings", function() {
				// The structural half of the claim above: SQLTokenStorage cannot be reaching for qb
				// (or anything else) behind our backs.
				//
				// What this bundle CANNOT prove is that the module runs with qb genuinely absent —
				// the harness installs qb so the QBTokenStorage specs have something to run
				// against. That check is a manual one, in an app without qb.
				var properties = getMetadata( getInstance( "SQLTokenStorage@rememberMe" ) ).properties;
				var injections = [];
				for ( var prop in properties ) {
					arrayAppend( injections, structKeyExists( prop, "inject" ) ? prop.inject : "" );
				}

				expect( injections ).toBe( [ "coldbox:modulesettings:rememberMe" ] );
			} );

			it( "resolves the configured userServiceClass", function() {
				var settings    = getInstance( dsl = "coldbox:modulesettings:rememberMe" );
				var userService = getInstance( dsl = settings.userServiceClass );

				expect( userService ).toBeComponent();
				// The contract the module's interface declares
				expect( userService ).toHaveKey( "retrieveUserById" );
			} );

			it( "resolves the configured tokenStorageClass to the ITokenStorage contract", function() {
				var settings = getInstance( dsl = "coldbox:modulesettings:rememberMe" );
				var storage  = getInstance( dsl = settings.tokenStorageClass );

				expect( storage ).toBeComponent();

				// The contract interfaces/ITokenStorage.cfc declares. Adobe cannot chain a method
				// off an array literal, so assign first.
				var contract = [
					"create",
					"getBySelector",
					"updateUsage",
					"deleteBySelector",
					"deleteByUserId",
					"deleteAll",
					"deleteExpiredBefore"
				];
				for ( var method in contract ) {
					expect( storage ).toHaveKey( method );
				}
			} );

		} );

	}

}
