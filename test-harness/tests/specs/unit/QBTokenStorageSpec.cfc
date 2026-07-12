/**
 * Unit specs for the default qb-backed storage — settings-derivation only.
 * No database, no qb: getTable()/getQueryOptions() are pure functions of the settings struct,
 * which is exactly why they exist (the datasource option must not be built at wiring time).
 */
component extends="tests.resources.BaseUnitSpec" {

	function run() {

		describe( "QBTokenStorage settings derivation", function() {

			beforeEach( function( currentSpec ) {
				variables.storage = buildStorage();
			} );

			describe( "getTable()", function() {

				it( "returns the configured table name", function() {
					expect( storage.getTable() ).toBe( "user_remember" );
				} );

				it( "honours a custom table setting", function() {
					var custom = buildStorage( { table : "my_tokens", datasource : "" } );
					expect( custom.getTable() ).toBe( "my_tokens" );
				} );

			} );

			describe( "getQueryOptions()", function() {

				it( "is an empty struct when no datasource is configured, so the engine uses the application default", function() {
					expect( storage.getQueryOptions() ).toBeEmpty();
				} );

				it( "carries the datasource when one is configured", function() {
					var custom = buildStorage( { table : "user_remember", datasource : "myDS" } );
					expect( custom.getQueryOptions() ).toBe( { datasource : "myDS" } );
				} );

				it( "is derived per call, not snapshotted — a settings change is picked up immediately", function() {
					// The settings struct is shared by reference (coldbox:modulesettings DSL), so a
					// snapshot taken at wiring time would go stale. Guard the lazy behaviour.
					var settings = { table : "user_remember", datasource : "" };
					var lazy     = buildStorage( settings );

					expect( lazy.getQueryOptions() ).toBeEmpty();
					settings.datasource = "lateDS";
					expect( lazy.getQueryOptions() ).toBe( { datasource : "lateDS" } );
				} );

			} );

			it( "two instances with different settings are independent", function() {
				var a = buildStorage( { table : "table_a", datasource : "" } );
				var b = buildStorage( { table : "table_b", datasource : "dsB" } );

				expect( a.getTable() ).toBe( "table_a" );
				expect( b.getTable() ).toBe( "table_b" );
				expect( a.getQueryOptions() ).toBeEmpty();
				expect( b.getQueryOptions() ).toBe( { datasource : "dsB" } );
			} );

		} );

	}

	/**
	 * A QBTokenStorage with pinned settings and its private helpers exposed. Same pattern as
	 * BaseUnitSpec.buildService(): path from the WireBox binder, createMock() for independence,
	 * $property() to skip wiring.
	 */
	private function buildStorage( struct settings = { table : "user_remember", datasource : "" } ) {
		var storagePath = getWireBox()
			.getBinder()
			.getMapping( "QBTokenStorage@rememberMe" )
			.getPath();

		var storage = createMock( storagePath );

		storage.$property( "settings", "variables", arguments.settings );

		var privateMethods = [ "getTable", "getQueryOptions" ];
		for ( var method in privateMethods ) {
			makePublic( storage, method );
		}

		return storage;
	}

}
