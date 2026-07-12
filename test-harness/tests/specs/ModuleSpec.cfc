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

			it( "maps QBTokenStorage@rememberMe into WireBox", function() {
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
				expect( settings.tokenStorageClass ).toBe( "QBTokenStorage@rememberMe" );
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

			it( "declares qb as a module dependency and qb is installed", function() {
				var modules = getController().getModuleService().getModuleRegistry();
				expect( modules ).toHaveKey( "qb" );
				expect( getInstance( "QueryBuilder@qb" ) ).toBeComponent();
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
