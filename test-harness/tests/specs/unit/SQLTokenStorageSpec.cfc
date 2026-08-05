/**
 * Unit specs for the DEFAULT storage provider — settings derivation only.
 * No database: getTable()/getQueryOptions() are pure functions of the settings struct, which is
 * exactly why they exist (the datasource option must not be built at wiring time).
 *
 * The end-to-end proof that SQLTokenStorage reads and writes real rows lives in the integration
 * bundles. RecallSpec and PurgeSpec drive the wired service, and the wired service resolves this
 * provider by default, so they exercise every statement in the file against a real database.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run() {

		describe( "SQLTokenStorage settings derivation", function() {

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

				it( "allows a schema-qualified name", function() {
					var custom = buildStorage( { table : "dbo.user_remember", datasource : "" } );
					expect( custom.getTable() ).toBe( "dbo.user_remember" );
				} );

				it( "rejects a table name containing SQL punctuation", function() {
					// The table name is interpolated into the SQL string — an identifier cannot be a
					// bind parameter — so this allow-list is what qb's grammar wrapValue() used to
					// provide. It is not a user-input path, but it turns a typo into a clear error
					// instead of a baffling SQL syntax failure.
					var custom = buildStorage( { table : "user_remember; drop table users--", datasource : "" } );
					expect( function() {
						custom.getTable();
					} ).toThrow( type = "InvalidConfiguration" );
				} );

				it( "rejects square-bracket quoting, which was never supported", function() {
					// qb would have double-wrapped "[user_remember]" too.
					var custom = buildStorage( { table : "[user_remember]", datasource : "" } );
					expect( function() {
						custom.getTable();
					} ).toThrow( type = "InvalidConfiguration" );
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

				it( "returns a FRESH struct each call, so callers can add returntype/result to it", function() {
					// getBySelector() and deleteExpiredBefore() both mutate what they get back. If
					// this ever started returning a shared reference, those keys would accumulate
					// on every other call's options.
					var custom = buildStorage( { table : "user_remember", datasource : "myDS" } );

					var first        = custom.getQueryOptions();
					first.returntype = "array";

					expect( custom.getQueryOptions() ).toBe( { datasource : "myDS" } );
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
	 * An SQLTokenStorage with pinned settings and its private helpers exposed. Same pattern as
	 * BaseUnitSpec.buildService(): path from the WireBox binder, createMock() for independence,
	 * $property() to skip wiring.
	 */
	private function buildStorage( struct settings = { table : "user_remember", datasource : "" } ) {
		var storagePath = getWireBox()
			.getBinder()
			.getMapping( "SQLTokenStorage@rememberMe" )
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
