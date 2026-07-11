/**
 * Unit specs — the token/crypto/parsing core, with every collaborator swapped out.
 * No database, no qb, no cookies. Runs identically on every engine.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run() {

		describe( "RememberMeService token internals", function() {

			beforeEach( function( currentSpec ) {
				variables.service = buildService();
			} );

			describe( "encryptToken() / decryptToken()", function() {

				it( "round-trips a value", function() {
					var plain = "abc_123";
					expect( service.decryptToken( service.encryptToken( plain ) ) ).toBe( plain );
				} );

				it( "does not leak the plaintext into the ciphertext", function() {
					var plain = "selector_validator";
					expect( service.encryptToken( plain ) ).notToInclude( "selector" );
				} );

				it( "cannot be decrypted with a different key", function() {
					var token = service.encryptToken( "abc_123" );
					var other = buildService( duplicate( TEST_SETTINGS ).append( {
						tokenEncryptKey : "TCPnMLWo6BAMPKfEpBcCPl0LNs9Xhr8DVEpEqSAe6Xk="
					} ) );

					expect( function() {
						other.decryptToken( token );
					} ).toThrow();
				} );

			} );

			describe( "hashValidator()", function() {

				it( "honours settings.validatorHashAlgorithm", function() {
					expect( service.hashValidator( "hello" ) ).toBe( hash( "hello", "MD5" ) );
				} );

				it( "produces a 32-char hash for MD5, matching the column width", function() {
					expect( service.hashValidator( createUuid() ).len() ).toBe( 32 );
				} );

				it( "uses a different algorithm when configured to", function() {
					var sha = buildService( duplicate( TEST_SETTINGS ).append( {
						validatorHashAlgorithm : "SHA-256"
					} ) );
					expect( sha.hashValidator( "hello" ) ).toBe( hash( "hello", "SHA-256" ) );
				} );

			} );

			describe( "parseToken()", function() {

				it( "splits the token on the underscore and hashes the validator half", function() {
					var selector  = createUuid();
					var validator = createUuid();
					var parsed    = service.parseToken( service.encryptToken( selector & "_" & validator ) );

					expect( parsed.selector ).toBe( selector );
					// The cookie carries the RAW validator; what we compare against the DB is its hash.
					expect( parsed.hashedValidator ).toBe( hash( validator, "MD5" ) );
					expect( parsed.hashedValidator ).notToBe( validator );
				} );

			} );

			describe( "isMatch()", function() {

				// Regression: this was inverted (returned true when the values DIFFERED), which
				// silently disabled the validator check in recallMe() entirely.
				it( "is true when the hashes are equal", function() {
					var h = hash( "abc", "MD5" );
					expect( service.isMatch( h, h ) ).toBeTrue();
				} );

				it( "is false when the hashes differ", function() {
					expect( service.isMatch( hash( "abc", "MD5" ), hash( "xyz", "MD5" ) ) ).toBeFalse();
				} );

				it( "is case-sensitive", function() {
					expect( service.isMatch( "ABCDEF", "abcdef" ) ).toBeFalse();
				} );

			} );

			describe( "isValidToken()", function() {

				it( "accepts a well-formed token", function() {
					var token = service.encryptToken( createUuid() & "_" & createUuid() );
					expect( service.isValidToken( token ) ).toBeTrue();
				} );

				it( "rejects a garbage string", function() {
					expect( service.isValidToken( "not-a-token" ) ).toBeFalse();
				} );

				it( "rejects an empty string", function() {
					expect( service.isValidToken( "" ) ).toBeFalse();
				} );

				it( "rejects a token encrypted with a different key", function() {
					var other = buildService( duplicate( TEST_SETTINGS ).append( {
						tokenEncryptKey : "TCPnMLWo6BAMPKfEpBcCPl0LNs9Xhr8DVEpEqSAe6Xk="
					} ) );
					var foreignToken = other.encryptToken( createUuid() & "_" & createUuid() );

					expect( service.isValidToken( foreignToken ) ).toBeFalse();
				} );

				it( "rejects a decryptable token with no underscore separator", function() {
					expect( service.isValidToken( service.encryptToken( "nounderscorehere" ) ) ).toBeFalse();
				} );

			} );

			describe( "getUserService()", function() {

				it( "throws IncompleteConfiguration when userServiceClass is not set", function() {
					var unconfigured = buildService( duplicate( TEST_SETTINGS ).append( {
						userServiceClass : ""
					} ) );

					expect( function() {
						unconfigured.getUserService();
					} ).toThrow( type = "IncompleteConfiguration" );
				} );

				it( "resolves the configured class through WireBox and memoises it", function() {
					var fakeUserService = createStub();
					var mockWireBox     = createStub().$( "getInstance", fakeUserService );

					service.$property( "wirebox", "variables", mockWireBox );

					expect( service.getUserService() ).toBe( fakeUserService );
					expect( service.getUserService() ).toBe( fakeUserService );

					// Memoised — WireBox is only consulted once, not once per call.
					expect( mockWireBox.$count( "getInstance" ) ).toBe( 1 );
				} );

			} );

			describe( "getBySelector()", function() {

				it( "short-circuits to an empty struct for an empty selector without touching qb", function() {
					// qb was never injected on this mock, so if the guard fails this throws.
					expect( service.getBySelector( "" ) ).toBeEmpty();
				} );

			} );

		} );

	}

}
