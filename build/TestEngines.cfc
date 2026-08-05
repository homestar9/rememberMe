/**
 * Runs the whole test suite on every engine, one after another.
 *
 * Run it with: box run-script test:engines
 *
 * Do this before a release. It is deliberately not part of the release itself: an engine that
 * fails to start should not stop a publish, and the release already runs the suite once on
 * whichever engine is up.
 *
 * Every engine shares the same port, so this runs strictly in order: stop everything, start
 * one engine, wait for it to answer, run the suite, stop it, move to the next. Expect it to
 * take a while. The first run of an engine also downloads it, which takes longer still.
 *
 * Every engine gets its turn even when an earlier one fails, so one broken engine never hides
 * the others. The end of the run prints a line per engine, and the task still exits with an
 * error if any of them failed.
 *
 * List your engines in build/build.json.
 */
component {

	/**
	 * init
	 *
	 * Loads the settings.
	 */
	function init(){
		variables.config = new BuildConfig( getDirectoryFromPath( getCurrentTemplatePath() ) );
		variables.s      = variables.config.getSettings();
		return this;
	}

	/**
	 * run
	 *
	 * Runs the suite on each engine in turn. Every engine gets its turn even when an earlier one
	 * fails. Prints a line per engine at the end and errors out if any of them failed, so a
	 * failure still stops CI and the release. Leaves every server stopped either way.
	 */
	function run(){
		if ( !arrayLen( variables.s.engines ) ) {
			return fail(
				"No engines are listed in build/build.json.",
				[
					'"engines": [',
					'    { "name": "Lucee 5",    "configFile": "server-lucee@5.json" },',
					'    { "name": "Adobe 2023", "configFile": "server-adobe@2023.json" }',
					']',
					"",
					"Each configFile is a server json file in your project root.",
					"Every engine you list is run, in the order you list them."
				],
				"Add them to build/build.json like this"
			);
		}

		var results = [];
		var started = getTickCount();

		// Only one server can hold the port, and we do not know which one is up.
		stopAllEngines();

		for ( var engine in variables.s.engines ) {
			var engineName  = engine.name ?: engine.configFile;
			var engineStart = getTickCount();
			print.line().boldBlueLine( "=== #engineName# (#engine.configFile#) ===" ).toConsole();

			var startResult = startEngine( engine, engineName );
			if ( !startResult.ok ) {
				results.append( recordFailure( engineName, engineStart, startResult.reason ) );
				continue;
			}

			var warmUpResult = warmUp( engine, engineName );
			if ( !warmUpResult.ok ) {
				results.append( recordFailure( engineName, engineStart, warmUpResult.reason ) );
				continue;
			}

			print.blueLine( "Running the suite on #engineName#..." ).toConsole();
			var suiteFailed = false;
			try {
				command( "testbox run" )
					.params( runner = variables.s.testRunner, verbose = false )
					.run();
				suiteFailed = ( shell.getExitCode() != 0 );
			} catch ( any e ) {
				suiteFailed = true;
			}

			stopEngine( engine.configFile );

			if ( suiteFailed ) {
				results.append( recordFailure( engineName, engineStart, "the suite failed" ) );
				continue;
			}

			var minutes = numberFormat( ( getTickCount() - engineStart ) / 60000, "0.9" );
			results.append( {
				"name"    : engineName,
				"passed"  : true,
				"minutes" : minutes,
				"reason"  : ""
			} );
			print.boldGreenLine( "#engineName#: passed in #minutes# min." ).toConsole();
		}

		return report( results, started );
	}

	/********************************************* PRIVATE HELPERS *********************************************/

	/**
	 * startEngine
	 *
	 * Starts one engine's server. Returns { ok, reason } rather than stopping the run, so the
	 * sweep can record the failure and move on to the next engine.
	 *
	 * @engine     The engine entry from build.json.
	 * @engineName The name to show.
	 */
	private struct function startEngine( required struct engine, required string engineName ){
		// Make sure the port is actually free first. Stopping a server returns before the old
		// process lets go of the port, and starting the next one then fails for a reason that
		// has nothing to do with the engine.
		waitForPortToFree( arguments.engineName );

		var startFailed = false;
		var startError  = "";
		try {
			command( "server start" )
				.params( serverConfigFile = arguments.engine.configFile )
				.run();
			startFailed = ( shell.getExitCode() != 0 );
		} catch ( any e ) {
			startFailed = true;
			startError  = e.message;
		}
		if ( startFailed ) {
			print
				.line()
				.boldLine( "Why a server will not start, usually:" )
				.yellowLine( "  the file is missing from your project root" )
				.yellowLine( "  another server still holds the port" )
				.yellowLine( "  the engine could not be downloaded" )
				.line()
				.boldLine( "Try it by hand to see the real reason:" )
				.yellowLine( "  box server start serverConfigFile=#arguments.engine.configFile#" )
				.line()
				.toConsole();
			// The start may have got far enough to hold the port. Clear it, or the next
			// engine in the sweep fails for a reason that has nothing to do with it.
			stopEngine( arguments.engine.configFile );
			return {
				"ok"     : false,
				"reason" : "would not start" & ( len( startError ) ? ": " & startError : "" )
			};
		}

		return { "ok" : true, "reason" : "" };
	}

	/**
	 * waitForPortToFree
	 *
	 * Waits until nothing answers on the test port, so the next engine is not started while the
	 * last one is still letting go of it. Gives up after a short wait and lets the start attempt
	 * produce the real error.
	 *
	 * @engineName The engine about to start, for the message.
	 */
	private function waitForPortToFree( required string engineName ){
		var probeUrl = variables.config.probeUrl();
		for ( var attempt = 1; attempt <= 12; attempt++ ) {
			var answered = false;
			try {
				cfhttp(
					url          = probeUrl,
					method       = "GET",
					timeout      = 5,
					throwonerror = false,
					redirect     = false,
					result       = "local.probe"
				);
				answered = ( val( local.probe.statuscode ?: "0" ) > 0 );
			} catch ( any e ) {
				answered = false;
			}
			if ( !answered ) {
				return;
			}
			if ( attempt == 1 ) {
				print.yellowLine( "Waiting for the previous server to release the port..." ).toConsole();
			}
			sleep( 5000 );
		}
		print
			.yellowLine( "Something still answers on the port. Starting #arguments.engineName# anyway." )
			.toConsole();
	}

	/**
	 * warmUp
	 *
	 * Waits until the site answers, so the suite never runs against a server that is still
	 * starting up. A half-started app produces failures that look real but are not. Returns
	 * { ok, reason } so the sweep can record the failure and move on to the next engine.
	 *
	 * @engine     The engine entry from build.json.
	 * @engineName The name to show.
	 */
	private struct function warmUp( required struct engine, required string engineName ){
		var attempts = variables.s.warmup.attempts;
		var delay    = variables.s.warmup.delaySeconds;
		var probeUrl = variables.config.probeUrl();

		print.blueLine( "Waiting for #arguments.engineName# (up to #attempts * delay# seconds)..." ).toConsole();
		var lastStatus = 0;
		for ( var attempt = 1; attempt <= attempts; attempt++ ) {
			var httpResult = "";
			try {
				cfhttp(
					url          = probeUrl,
					method       = "GET",
					timeout      = 60,
					throwonerror = false,
					redirect     = false,
					result       = "local.httpResult"
				);
				lastStatus = val( httpResult.statuscode ?: "0" );
			} catch ( any e ) {
				lastStatus = 0;
			}
			// Anything in the 200s or 300s means the site answered.
			if ( lastStatus >= 200 && lastStatus < 400 ) {
				print.greenLine( "#arguments.engineName# is up (status #lastStatus#)." ).toConsole();
				return { "ok" : true, "reason" : "" };
			}
			sleep( delay * 1000 );
		}

		stopEngine( arguments.engine.configFile );
		print
			.line()
			.yellowLine(
				"A repeating 500 usually means the app will not start on this engine. Start it by hand and read the log:"
			)
			.yellowLine( "  box server start serverConfigFile=#arguments.engine.configFile#" )
			.line()
			.toConsole();

		return { "ok" : false, "reason" : "never answered (last status: #lastStatus#)" };
	}

	/**
	 * stopAllEngines
	 *
	 * Stops every listed engine, ignoring failures. At most one is running, and stopping one
	 * that is not running only prints a complaint.
	 */
	private function stopAllEngines(){
		print.blueLine( "Stopping any running server..." ).toConsole();
		for ( var engine in variables.s.engines ) {
			stopEngine( engine.configFile );
		}
	}

	/**
	 * stopEngine
	 *
	 * Stops one server quietly. A failure here never matters: either it was not running, or
	 * the next start will complain about the port anyway.
	 *
	 * @configFile The server json file for the engine to stop.
	 */
	private function stopEngine( required string configFile ){
		try {
			command( "server stop" ).params( serverConfigFile = arguments.configFile ).run();
		} catch ( any e ) {
			// Not running, nothing to do.
		}
	}

	/**
	 * recordFailure
	 *
	 * Builds the result entry for an engine that failed and prints the one-line reason.
	 *
	 * @engineName  The name to show.
	 * @engineStart The tick count from when this engine's turn began.
	 * @reason      Why it failed, in a few words.
	 */
	private struct function recordFailure( required string engineName, required numeric engineStart, required string reason ){
		var minutes = numberFormat( ( getTickCount() - arguments.engineStart ) / 60000, "0.9" );
		print.boldRedLine( "#arguments.engineName#: FAILED after #minutes# min -- #arguments.reason#" ).toConsole();
		return {
			"name"    : arguments.engineName,
			"passed"  : false,
			"minutes" : minutes,
			"reason"  : arguments.reason
		};
	}

	/**
	 * report
	 *
	 * Prints a line per engine and ends the task. Errors out when any engine failed, so the
	 * exit code still says the sweep was not clean.
	 *
	 * @results One entry per engine, in the order they ran.
	 * @started The tick count from when the whole sweep began.
	 */
	private function report( required array results, required numeric started ){
		var totalMinutes = numberFormat( ( getTickCount() - arguments.started ) / 60000, "0.9" );
		var failed       = arguments.results.filter( function( result ){
			return !result.passed;
		} );

		print.line().boldLine( "Results (#totalMinutes# min total):" ).toConsole();
		for ( var result in arguments.results ) {
			if ( result.passed ) {
				print.greenLine( "  PASSED  #result.name# (#result.minutes# min)" ).toConsole();
			} else {
				print.redLine( "  FAILED  #result.name# (#result.minutes# min) -- #result.reason#" ).toConsole();
			}
		}
		print.line().toConsole();

		if ( !failed.len() ) {
			print.boldGreenLine( "All #arguments.results.len()# engines passed." ).toConsole();
			return;
		}

		var failedNames = failed.map( function( result ){
			return result.name;
		} );

		return error(
			"#failed.len()# of #arguments.results.len()# engines failed: "
			& failedNames.toList( ", " ) & "."
		);
	}

	/**
	 * fail
	 *
	 * Stops the task, printing guidance that spans several lines.
	 *
	 * CommandBox's error() removes line breaks from its message, so anything longer than a
	 * sentence arrives as one run-together block. The guidance is printed first, where it keeps
	 * its shape, and error() is left with the single line that says what went wrong.
	 *
	 * @summary One line saying what went wrong.
	 * @detail  Lines of guidance to print first.
	 * @heading A short label for the guidance.
	 */
	private function fail( required string summary, array detail = [], string heading = "What to do" ){
		if ( arrayLen( arguments.detail ) ) {
			print.line().boldLine( arguments.heading & ":" ).toConsole();
			for ( var line in arguments.detail ) {
				print.yellowLine( "  " & line ).toConsole();
			}
			print.line().toConsole();
		}
		return error( arguments.summary );
	}
}
