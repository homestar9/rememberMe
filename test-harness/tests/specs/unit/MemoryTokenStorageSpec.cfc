/**
 * Unit specs for the in-memory storage provider.
 *
 * Lives in unit/ rather than integration/ because there is nothing to integrate with — the whole
 * store is a struct. That is also why this is the one provider whose ITokenStorage contract can be
 * driven directly and completely here: the SQL providers need a real database, so their contract
 * coverage comes from RecallSpec and PurgeSpec instead.
 *
 * Because MemoryTokenStorage doubles as the copy-me example for host apps writing their own
 * provider, these specs are deliberately written against the CONTRACT (interfaces/ITokenStorage.cfc)
 * rather than against the struct inside. Anyone building a provider can lift this bundle wholesale
 * and point buildStorage() at their class.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run() {

		describe( "MemoryTokenStorage", function() {

			beforeEach( function( currentSpec ) {
				variables.storage = buildStorage();
			} );

			describe( "create() and getBySelector()", function() {

				it( "round-trips every key of the token struct", function() {
					var token = aToken();
					storage.create( token );

					var found = storage.getBySelector( token.selector );

					for ( var key in token ) {
						expect( found ).toHaveKey( key );
						expect( found[ key ] ).toBe( token[ key ], "key [#key#] did not round-trip" );
					}
				} );

				it( "returns an EMPTY STRUCT for an unknown selector, never null", function() {
					expect( storage.getBySelector( createUuid() ) ).toBeEmpty();
				} );

				it( "hands back a copy, so a caller cannot mutate the store through it", function() {
					var token = aToken();
					storage.create( token );

					var found  = storage.getBySelector( token.selector );
					found.userId = 999;

					expect( storage.getBySelector( token.selector ).userId ).toBe( token.userId );
				} );

				it( "keeps a copy, so mutating the struct you passed in does not reach the store", function() {
					var token = aToken();
					storage.create( token );
					token.userId = 999;

					expect( storage.getBySelector( token.selector ).userId ).toBe( 1 );
				} );

			} );

			describe( "updateUsage()", function() {

				it( "stamps the audit keys and leaves everything else alone", function() {
					var token = aToken();
					storage.create( token );

					var stampedAt = dateAdd( "n", 5, now() );
					storage.updateUsage( token.selector, {
						ipAddress : "10.0.0.9",
						userAgent : "a different browser",
						lastUsedDate : stampedAt,
						modifiedDate : stampedAt
					} );

					var found = storage.getBySelector( token.selector );

					expect( found.ipAddress ).toBe( "10.0.0.9" );
					expect( found.userAgent ).toBe( "a different browser" );
					expect( found.lastUsedDate ).toBe( stampedAt );
					expect( found.modifiedDate ).toBe( stampedAt );

					// Untouched — there is no token rotation, and the expiry does not move.
					expect( found.selector ).toBe( token.selector );
					expect( found.hashedValidator ).toBe( token.hashedValidator );
					expect( found.expirationDate ).toBe( token.expirationDate );
					expect( found.createdDate ).toBe( token.createdDate );
				} );

				it( "does nothing for an unknown selector, the way an UPDATE ... WHERE would", function() {
					expect( function() {
						storage.updateUsage( createUuid(), {
							ipAddress : "10.0.0.9",
							userAgent : "spec",
							lastUsedDate : now(),
							modifiedDate : now()
						} );
					} ).notToThrow();

					expect( storage.count() ).toBe( 0 );
				} );

			} );

			describe( "the delete methods", function() {

				it( "deleteBySelector removes only that token", function() {
					var keep   = aToken();
					var remove = aToken();
					storage.create( keep );
					storage.create( remove );

					storage.deleteBySelector( remove.selector );

					expect( storage.getBySelector( remove.selector ) ).toBeEmpty();
					expect( storage.getBySelector( keep.selector ) ).notToBeEmpty();
				} );

				it( "deleteBySelector on an unknown selector is a no-op", function() {
					storage.create( aToken() );
					storage.deleteBySelector( createUuid() );
					expect( storage.count() ).toBe( 1 );
				} );

				it( "deleteByUserId removes every token for that user and no others", function() {
					storage.create( aToken( userId = 1 ) );
					storage.create( aToken( userId = 1 ) );
					var otherUser = aToken( userId = 2 );
					storage.create( otherUser );

					storage.deleteByUserId( 1 );

					expect( storage.count() ).toBe( 1 );
					expect( storage.getBySelector( otherUser.selector ) ).notToBeEmpty();
				} );

				it( "deleteAll empties the store", function() {
					storage.create( aToken() );
					storage.create( aToken() );

					storage.deleteAll();

					expect( storage.count() ).toBe( 0 );
				} );

			} );

			describe( "deleteExpiredBefore()", function() {

				it( "deletes tokens that expired before the cutoff and returns how many", function() {
					var expired = aToken( expirationDate = dateAdd( "d", -10, now() ) );
					var live    = aToken( expirationDate = dateAdd( "d", 10, now() ) );
					storage.create( expired );
					storage.create( live );

					var deleted = storage.deleteExpiredBefore( now() );

					expect( deleted ).toBe( 1 );
					expect( storage.getBySelector( expired.selector ) ).toBeEmpty();
					expect( storage.getBySelector( live.selector ) ).notToBeEmpty();
				} );

				it( "returns 0 and deletes nothing when no token has expired", function() {
					storage.create( aToken( expirationDate = dateAdd( "d", 10, now() ) ) );

					expect( storage.deleteExpiredBefore( now() ) ).toBe( 0 );
					expect( storage.count() ).toBe( 1 );
				} );

				it( "honours the cutoff date rather than 'now' — the grace period is the service's business", function() {
					// RememberMeService.purgeExpired() computes now() minus purgeGraceDays and hands
					// the result over. Storage must not second-guess it.
					var expiredYesterday = aToken( expirationDate = dateAdd( "d", -1, now() ) );
					storage.create( expiredYesterday );

					// A cutoff a week back: the token expired AFTER it, so it stays.
					expect( storage.deleteExpiredBefore( dateAdd( "d", -7, now() ) ) ).toBe( 0 );
					expect( storage.count() ).toBe( 1 );
				} );

			} );

		} );

	}

	/**
	 * A MemoryTokenStorage built the same way as the other storage bundles: path from the WireBox
	 * binder, createMock() for a fresh instance per spec.
	 *
	 * createMock() rather than getInstance() on purpose. The real mapping is asSingleton, so
	 * getInstance() would hand every spec the SAME store and state would leak between them.
	 */
	private function buildStorage() {
		var storagePath = getWireBox()
			.getBinder()
			.getMapping( "MemoryTokenStorage@rememberMe" )
			.getPath();

		return createMock( storagePath );
	}

	/**
	 * A token struct shaped exactly like the one RememberMeService.rememberMe() builds.
	 */
	private struct function aToken( numeric userId = 1, date expirationDate = dateAdd( "d", 30, now() ) ) {
		return {
			userId : arguments.userId,
			selector : createUuid(),
			hashedValidator : hash( createUuid(), "MD5" ),
			ipAddress : "127.0.0.1",
			userAgent : "spec",
			createdDate : now(),
			modifiedDate : now(),
			expirationDate : arguments.expirationDate
		};
	}

}
