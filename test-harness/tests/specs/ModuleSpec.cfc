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

			it( "declares its documented settings", function() {
				var settings = getInstance( dsl = "coldbox:modulesettings:rememberMe" );

				expect( settings ).toHaveKey( "userServiceClass" );
				expect( settings ).toHaveKey( "tokenEncryptKey" );
				expect( settings ).toHaveKey( "tokenEncryptAlgorithm" );
				expect( settings ).toHaveKey( "validatorHashAlgorithm" );
				expect( settings ).toHaveKey( "days" );

				// The harness overrides these; the defaults themselves live in ModuleConfig.cfc
				expect( settings.tokenEncryptAlgorithm ).toBe( "aes" );
				expect( settings.validatorHashAlgorithm ).toBe( "MD5" );
				expect( settings.days ).toBe( 30 );
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

		} );

	}

}
