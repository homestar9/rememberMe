/**
 * Integration specs for purgeExpired() and the scheduled purge task.
 * Real SQL Server, real qb — rows are aged via direct SQL the same way RecallSpec
 * ages its expired-token fixture.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	function run() {

		describe( "purging expired tokens", function() {

			// Registered HERE, not as a component-level beforeEach() method: TestBox only fires
			// the closures declared inside a describe() for a BDD bundle. See BaseIntegrationSpec.
			beforeEach( function( currentSpec ) {
				resetState();
			} );

			afterEach( function( currentSpec ) {
				resetState();
			} );

			describe( "purgeExpired()", function() {

				it( "deletes rows expired more than graceDays ago and returns the count", function() {
					// Three users; rememberMe() forgets the current cookie's row first, so the
					// cookie must be cleared between calls for the rows to accumulate.
					service.rememberMe( 1 );
					clearRememberCookie();
					service.rememberMe( 2 );
					clearRememberCookie();
					service.rememberMe( 3 );
					expect( tokenCount() ).toBe( 3 );

					var tokens = allTokens();
					ageToken( tokens[ 1 ].selector, 48 ); // well past the 1-day grace window
					ageToken( tokens[ 2 ].selector, 12 ); // expired, but inside the grace window
					// tokens[ 3 ] keeps its future expirationDate

					expect( service.purgeExpired() ).toBe( 1 );

					var remaining = allTokens();
					expect( remaining.len() ).toBe( 2 );
					expect( remaining[ 1 ].selector ).toBe( tokens[ 2 ].selector );
					expect( remaining[ 2 ].selector ).toBe( tokens[ 3 ].selector );
				} );

				it( "keeps rows inside the grace window", function() {
					service.rememberMe( 1 );
					ageToken( allTokens()[ 1 ].selector, 12 );

					expect( service.purgeExpired() ).toBe( 0 );
					expect( tokenCount() ).toBe( 1 );
				} );

				it( "honors an explicit graceDays argument", function() {
					service.rememberMe( 1 );
					ageToken( allTokens()[ 1 ].selector, 12 );

					expect( service.purgeExpired( 0 ) ).toBe( 1 );
					expect( tokenCount() ).toBe( 0 );
				} );

				it( "returns 0 and deletes nothing when no rows qualify", function() {
					service.rememberMe( 1 );

					expect( service.purgeExpired() ).toBe( 0 );
					expect( tokenCount() ).toBe( 1 );
				} );

			} );

			describe( "the scheduled task", function() {

				it( "purges stale rows when it fires", function() {
					service.rememberMe( 1 );
					clearRememberCookie();
					service.rememberMe( 2 );

					var tokens = allTokens();
					ageToken( tokens[ 1 ].selector, 48 );

					var task = getController()
						.getSchedulerService()
						.getSchedulers()[ "cbScheduler@rememberMe" ]
						.getTaskRecord( "rememberMe-purge-expired-tokens" )
						.task;

					// force = true bypasses the everyDayAt schedule and the when() constraint,
					// running the task's closure right now on this thread.
					task.run( force = true );

					var remaining = allTokens();
					expect( remaining.len() ).toBe( 1 );
					expect( remaining[ 1 ].selector ).toBe( tokens[ 2 ].selector );
				} );

			} );

		} );

	}

	/**
	 * Back-date a row's expirationDate so it expired `hoursPast` hours ago. Hours, not days:
	 * with the default 1-day grace window, day-granularity fixtures would sit exactly on the
	 * cutoff and flap with execution timing.
	 */
	private void function ageToken( required string selector, required numeric hoursPast ) {
		queryExecute(
			"update #variables.TABLE# set expirationDate = :expired where selector = :selector",
			{
				expired  : { value : dateAdd( "h", -arguments.hoursPast, now() ), cfsqltype : "timestamp" },
				selector : { value : arguments.selector, cfsqltype : "varchar" }
			}
		);
	}

}
