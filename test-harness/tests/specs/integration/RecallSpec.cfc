/**
 * Integration specs — real SQL Server, real qb, real cookie scope.
 * Drives the full rememberMe() -> recallMe() -> forgetMe() lifecycle.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	function run() {

		describe( "RememberMeService lifecycle", function() {

			// Registered HERE, not as a component-level beforeEach() method: TestBox only fires
			// the closures declared inside a describe() for a BDD bundle. See BaseIntegrationSpec.
			beforeEach( function( currentSpec ) {
				resetState();
				recallSpy().reset();
			} );

			afterEach( function( currentSpec ) {
				resetState();
			} );

			describe( "rememberMe()", function() {

				it( "persists a token row and sets the cookie", function() {
					service.rememberMe( 1 );

					var tokens = allTokens();
					expect( tokens.len() ).toBe( 1 );
					expect( tokens[ 1 ].userId ).toBe( 1 );
					expect( tokens[ 1 ].selector ).notToBeEmpty();
					expect( tokens[ 1 ].hashedValidator ).notToBeEmpty();

					expect( service.cookieExists() ).toBeTrue();
					expect( service.isValidToken( service.getCookie() ) ).toBeTrue();
				} );

				it( "stores the HASHED validator in the database but puts the RAW one in the cookie", function() {
					service.rememberMe( 1 );

					var row       = allTokens()[ 1 ];
					var plaintext = decrypt(
						service.getCookie(),
						getInstance( dsl = "coldbox:modulesettings:rememberMe" ).tokenEncryptKey,
						"aes",
						"Base64"
					);
					var rawValidator = plaintext.listGetAt( 2, "_" );

					// The cookie must NOT carry the value the database holds...
					expect( rawValidator ).notToBe( row.hashedValidator );
					// ...it must carry its pre-image. This asymmetry is the point of the scheme:
					// a stolen database yields hashes an attacker cannot present back to us.
					expect( hash( rawValidator, "MD5" ) ).toBe( row.hashedValidator );
					expect( plaintext.listGetAt( 1, "_" ) ).toBe( row.selector );
				} );

				it( "populates modifiedDate on insert (the column is NOT NULL with no default)", function() {
					service.rememberMe( 1 );

					var row = allTokens()[ 1 ];
					expect( isDate( row.createdDate ) ).toBeTrue();
					expect( isDate( row.modifiedDate ) ).toBeTrue();
					// lastUsedDate stays null until the token is actually recalled
					expect( row.lastUsedDate ).toBeEmpty();
				} );

				it( "sets an expiration `days` in the future", function() {
					service.rememberMe( 1 );

					var row  = allTokens()[ 1 ];
					var days = getInstance( dsl = "coldbox:modulesettings:rememberMe" ).days;

					expect( dateDiff( "d", now(), row.expirationDate ) ).toBeGTE( days - 1 );
					expect( dateDiff( "d", now(), row.expirationDate ) ).toBeLTE( days );
				} );

				it( "purges any previous token for the browser before issuing a new one", function() {
					service.rememberMe( 1 );
					var firstSelector = allTokens()[ 1 ].selector;

					service.rememberMe( 1 );

					var tokens = allTokens();
					expect( tokens.len() ).toBe( 1 );
					expect( tokens[ 1 ].selector ).notToBe( firstSelector );
				} );

				it( "issues a distinct selector and validator each time", function() {
					service.rememberMe( 1 );
					var first = allTokens()[ 1 ];

					// Drop the cookie so rememberMe()'s internal forgetMe() can't find the old row
					// to purge — leaving both rows in place to compare.
					clearRememberCookie();
					service.rememberMe( 1 );

					var rows = allTokens();
					expect( rows.len() ).toBe( 2 );
					var second = rows[ 2 ];

					expect( second.selector ).notToBe( first.selector );
					expect( second.hashedValidator ).notToBe( first.hashedValidator );
				} );

			} );

			describe( "recallMe()", function() {

				it( "returns the user for a valid token", function() {
					service.rememberMe( 7 );

					var user = service.recallMe();

					expect( user ).toBeComponent();
					expect( user.getId() ).toBe( 7 );
					expect( user.isLoaded() ).toBeTrue();
				} );

				it( "stamps the audit columns on the recalled row", function() {
					service.rememberMe( 1 );
					expect( allTokens()[ 1 ].lastUsedDate ).toBeEmpty();

					service.recallMe();

					var row = allTokens()[ 1 ];
					expect( isDate( row.lastUsedDate ) ).toBeTrue();
					expect( isDate( row.modifiedDate ) ).toBeTrue();
					expect( row.userAgent ).toBeString();
				} );

				// The module's one public event. RecallSpy is a real interceptor registered in
				// config/Coldbox.cfc — the same way a consuming app would listen.
				it( "announces onRecall with the user and userId", function() {
					service.rememberMe( 42 );
					expect( recallSpy().getCaptured() ).toBeEmpty();

					service.recallMe();

					var captured = recallSpy().getCaptured();
					expect( captured.len() ).toBe( 1 );
					expect( captured[ 1 ] ).toHaveKey( "user" );
					expect( captured[ 1 ] ).toHaveKey( "userId" );
					expect( captured[ 1 ].userId ).toBe( 42 );
					expect( captured[ 1 ].user.getId() ).toBe( 42 );
				} );

				it( "does not announce onRecall when the token is rejected", function() {
					putRememberCookie( forgeToken( createUuid(), createUuid() ) );

					try {
						service.recallMe();
					} catch ( InvalidToken e ) {
					}

					expect( recallSpy().getCaptured() ).toBeEmpty();
				} );

				it( "throws MissingCookie when there is no cookie", function() {
					expect( function() {
						service.recallMe();
					} ).toThrow( type = "MissingCookie" );
				} );

				it( "throws InvalidToken for a garbage cookie", function() {
					putRememberCookie( "this-is-not-an-encrypted-token" );

					expect( function() {
						service.recallMe();
					} ).toThrow( type = "InvalidToken" );
				} );

				it( "throws InvalidToken when the selector matches no row", function() {
					putRememberCookie( forgeToken( createUuid(), createUuid() ) );

					expect( function() {
						service.recallMe();
					} ).toThrow( type = "InvalidToken" );
				} );

				/**
				 * THE security regression test.
				 *
				 * Before the fix, isMatch() was inverted AND parseToken() double-hashed, and the two
				 * bugs cancelled: the validator comparison never rejected anything. A forged cookie
				 * carrying a REAL selector and a junk validator authenticated successfully.
				 *
				 * If this spec ever goes green-to-red, the validator check has been disabled again.
				 */
				it( "throws InvalidToken for a real selector with a forged validator", function() {
					service.rememberMe( 1 );
					var realSelector = allTokens()[ 1 ].selector;

					putRememberCookie( forgeToken( realSelector, createUuid() ) );

					expect( function() {
						service.recallMe();
					} ).toThrow( type = "InvalidToken" );
				} );

				it( "throws InvalidToken for an expired token", function() {
					service.rememberMe( 1 );
					var selector = allTokens()[ 1 ].selector;

					queryExecute(
						"update user_remember set expirationDate = :expired where selector = :selector",
						{
							expired  : { value : dateAdd( "d", -1, now() ), cfsqltype : "timestamp" },
							selector : { value : selector, cfsqltype : "varchar" }
						}
					);

					expect( function() {
						service.recallMe();
					} ).toThrow( type = "InvalidToken" );
				} );

			} );

			describe( "forgetMe()", function() {

				it( "deletes the row and clears the cookie", function() {
					service.rememberMe( 1 );
					expect( tokenCount() ).toBe( 1 );

					service.forgetMe();

					expect( tokenCount() ).toBe( 0 );
					expect( service.cookieExists() ).toBeFalse();
				} );

				it( "is safe to call when no cookie is present", function() {
					expect( service.cookieExists() ).toBeFalse();

					expect( function() {
						service.forgetMe();
					} ).notToThrow();
				} );

				it( "leaves a recalled session unable to recall again", function() {
					service.rememberMe( 1 );
					service.forgetMe();

					expect( function() {
						service.recallMe();
					} ).toThrow( type = "MissingCookie" );
				} );

			} );

			describe( "bulk deletes", function() {

				it( "deleteByUserId() removes only that user's tokens", function() {
					service.rememberMe( 1 );
					clearRememberCookie();
					service.rememberMe( 2 );
					expect( tokenCount() ).toBe( 2 );

					service.deleteByUserId( 1 );

					var remaining = allTokens();
					expect( remaining.len() ).toBe( 1 );
					expect( remaining[ 1 ].userId ).toBe( 2 );
				} );

				it( "deleteAll() empties the table", function() {
					service.rememberMe( 1 );
					clearRememberCookie();
					service.rememberMe( 2 );

					service.deleteAll();

					expect( tokenCount() ).toBe( 0 );
				} );

			} );

			describe( "getBySelector()", function() {

				it( "returns the row for a known selector", function() {
					service.rememberMe( 1 );
					var selector = allTokens()[ 1 ].selector;

					var row = service.getBySelector( selector );

					expect( row ).notToBeEmpty();
					expect( row.selector ).toBe( selector );
					expect( row.userId ).toBe( 1 );
				} );

				it( "returns an empty struct for an unknown selector", function() {
					expect( service.getBySelector( createUuid() ) ).toBeEmpty();
				} );

			} );

		} );

	}

}
