/**
 * Build process for ColdBox Modules
 * Adapt to your needs.
 */
component {

	/**
	 * Constructor
	 */
	function init(){
		// Setup Pathing
		variables.cwd          = getCWD().reReplace( "\.$", "" );
		variables.artifactsDir = cwd & "/.artifacts";
		variables.buildDir     = cwd & "/.tmp";
		// The embedded server's webroot is test-harness/, and box.json's start:* scripts all use
		// port 60301. These pointed at 60299 for years and could never have resolved. Use
		// 127.0.0.1, not localhost: on Windows localhost can resolve to IPv6 ::1 while CommandBox
		// binds the IPv4 loopback, and the runner preflight then times out (408) against a server
		// that is actually up.
		variables.apiDocsURL   = "http://127.0.0.1:60305/apidocs/";
		variables.testRunner   = "http://127.0.0.1:60305/tests/runner.cfm";

		/**
		 * Source excludes NOT added to the final binary.
		 *
		 * These are regex patterns run through reFindNoCase() against each top-level entry name in
		 * copy() below. reFindNoCase does a PARTIAL match, so an unanchored pattern matches anywhere
		 * in the name. That is a trap: a bare "modules" would also match "modules_app", which must
		 * ship (it carries the google submodule). Anchor anything whose name is a
		 * prefix of something we need to keep.
		 *
		 * The leading [\\/]? tolerates a separator in case getCWD() returns no trailing slash; without
		 * it, an anchored pattern would silently stop matching and start shipping what it excludes.
		 *
		 * Only TOP-LEVEL entries are tested (directoryList is called with recurse=false, and a
		 * directory that survives is copied whole). So a nested file cannot be excluded from here;
		 * keep generated secrets out of shipped directories in the first place.
		 *
		 * Keep shipping: config, handlers, includes, install, interceptors, layouts, lib, models,
		 * modules_app, udf, views, ModuleConfig.cfc, box.json, README.md
		 */
		variables.excludes = [
			// Build tooling + dependencies (never shipped; CommandBox reinstalls modules/ from box.json)
			"^[\\/]?build$",
			"^[\\/]?node_modules$",
			"^[\\/]?modules$",
			"^[\\/]?resources$",
			// Tests + local scratch
			"^[\\/]?test-harness$",
			"^[\\/]?tests$",
			"^[\\/]?test-results$",
			"^[\\/]?temp$",
			"^[\\/]?plans$",
			// Tooling config + dev docs
			"(package|package-lock)\.json",
			"webpack.config.js",
			"vite(st)?\.config\.js",
			"playwright\.config\.js",
			"server-.*\.json",
			"docker-compose.yml",
			"caffeinecms\.code-workspace",
			"(AGENTS|CLAUDE|DEVNOTES)\.md",
			"\.bak$",
			// Output of install/CreateAdmin.cfc: holds a real password hash, must never ship.
			"first-admin\.sql",
			// Every dotfile/dotdir (.git, .env, .npmrc, .artifacts, .tmp, ...)
			"^[\\/]?\..*"
		];

		// Cleanup + Init Build Directories
		[
			variables.buildDir,
			variables.artifactsDir
		].each( function( item ){
			if ( directoryExists( item ) ) {
				directoryDelete( item, true );
			}
			// Create directories
			directoryCreate( item, true, true );
		} );

		// Create Mappings
		fileSystemUtil.createMapping(
			"coldbox",
			variables.cwd & "test-harness/coldbox"
		);

		return this;
	}

	/**
	 * Run the build process: test, build source, docs, checksums
	 *
	 * @projectName The project name used for resources and slugs
	 * @version The version you are building
	 * @buldID The build identifier
	 * @branch The branch you are building. Empty (the default) resolves the CURRENT git branch at
	 *         build time so the artifact metadata never lies about what it was cut from.
	 */
	function run(
		required projectName,
		version = "1.0.0",
		buildID = createUUID(),
		branch  = ""
	){
		// Stamp the artifact with the branch it was actually cut from. Reading live git state (rather
		// than a hardcoded "development" default) means a build cut from main is labelled main and a
		// build cut from modernization is labelled modernization — the metadata cannot silently lie.
		if ( !len( trim( arguments.branch ) ) ) {
			arguments.branch = getCurrentBranch();
		}

		// Certify before packaging: a release-gate build must never produce an artifact that skipped
		// its tests. runTests() aborts the build on any failure. We preflight the runner first so an
		// unreachable server aborts with an ACCURATE message (server down != test regression) instead
		// of runTests()'s misleading "tests failed". The intentional escape hatch for CI/packaging on
		// a machine with no running CF engine + seeded database is to invoke target=buildSource
		// directly (see box.json build:docs for the target= pattern) — an explicit, visible opt-out,
		// never a silent skip.
		ensureTestRunnerReachable();
		runTests();

		// Create project mapping
		fileSystemUtil.createMapping( arguments.projectName, variables.cwd );

		// Build the source
		buildSource( argumentCollection = arguments );

		// API docs are deliberately NOT part of the default build. DocBox cannot resolve this
		// module's component paths (cms.models.*, quick.models.*) without mappings that were never
		// wired, so docs() dies mid-generation - and no apidocs ship in the module zip anyway. The
		// docs() target remains callable directly (target=docs) for whoever wires those mappings.

		// checksums
		buildChecksums();

		// Finalize Message
		print
			.line()
			.boldMagentaLine( "Build Process is done! Enjoy your build!" )
			.toConsole();
	}

	/**
	 * Run the test suites
	 */
	function runTests(){
		// Tests First, if they fail then exit
		print.blueLine( "Testing the package, please wait..." ).toConsole();

		// No outputFile/outputFormats: nothing consumes the JSON/JUnit reports, the exit code below
		// is what certifies the build, and the outputFile plumbing failed on Windows with a
		// "volume label syntax is incorrect" IOException from testbox-cli's own FileWrite.
		command( "testbox run" )
			.params(
				runner  = variables.testRunner,
				verbose = false
			)
			.run();

		// Check Exit Code?
		if ( shell.getExitCode() ) {
			return error( "Cannot continue building, tests failed!" );
		}
	}

	/**
	 * Build the source
	 *
	 * @projectName The project name used for resources and slugs
	 * @version The version you are building
	 * @buldID The build identifier
	 * @branch The branch you are building. Falls back to the current git branch when invoked directly
	 *         (e.g. target=buildSource) so a direct packaging run is still labelled honestly.
	 */
	function buildSource(
		required projectName,
		version = "1.0.0",
		buildID = createUUID(),
		branch  = ""
	){
		if ( !len( trim( arguments.branch ) ) ) {
			arguments.branch = getCurrentBranch();
		}
		// Build Notice ID
		print
			.line()
			.boldMagentaLine(
				"Building #arguments.projectName# v#arguments.version#+#arguments.buildID# from #cwd# using the #arguments.branch# branch."
			)
			.toConsole();

		ensureExportDir( argumentCollection = arguments );

		// Project Build Dir
		variables.projectBuildDir = variables.buildDir & "/#projectName#";
		directoryCreate(
			variables.projectBuildDir,
			true,
			true
		);

		// Copy source
		print.blueLine( "Copying source to build folder..." ).toConsole();
		copy(
			variables.cwd,
			variables.projectBuildDir
		);

		// Create build ID
		fileWrite(
			"#variables.projectBuildDir#/#projectName#-#version#+#buildID#",
			"Built with love on #dateTimeFormat( now(), "full" )#"
		);

		// Updating Placeholders
		print.greenLine( "Updating version identifier to #arguments.version#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "/#variables.projectBuildDir#/**",
				token       = "@build.version@",
				replacement = arguments.version
			)
			.run();

		print.greenLine( "Updating build identifier to #arguments.buildID#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "/#variables.projectBuildDir#/**",
				token       = ( arguments.branch == "master" ? "@build.number@" : "+@build.number@" ),
				replacement = ( arguments.branch == "master" ? arguments.buildID : "-snapshot" )
			)
			.run();

		// zip up source
		var destination = "#variables.exportsDir#/#projectName#-#version#.zip";
		print.greenLine( "Zipping code to #destination#" ).toConsole();
		cfzip(
			action    = "zip",
			file      = "#destination#",
			source    = "#variables.projectBuildDir#",
			overwrite = true,
			recurse   = true
		);

		// Copy box.json for convenience
		fileCopy(
			"#variables.projectBuildDir#/box.json",
			variables.exportsDir
		);
	}

	/**
	 * Produce the API Docs
	 */
	function docs(
		required projectName,
		version   = "1.0.0",
		outputDir = ".tmp/apidocs"
	){
		ensureExportDir( argumentCollection = arguments );

		// Create project mapping
		fileSystemUtil.createMapping( arguments.projectName, variables.cwd );
		// Generate Docs
		print.greenLine( "Generating API Docs, please wait..." ).toConsole();

		command( "docbox generate" )
			.params(
				"source"                = "models",
				"mapping"               = "models",
				"strategy-projectTitle" = "#arguments.projectName# v#arguments.version#",
				"strategy-outputDir"    = arguments.outputDir
			)
			.run();

		print.greenLine( "API Docs produced at #arguments.outputDir#" ).toConsole();

		var destination = "#variables.exportsDir#/#projectName#-docs-#version#.zip";
		print.greenLine( "Zipping apidocs to #destination#" ).toConsole();
		cfzip(
			action    = "zip",
			file      = "#destination#",
			source    = "#arguments.outputDir#",
			overwrite = true,
			recurse   = true
		);
	}

	/********************************************* PRIVATE HELPERS *********************************************/

	/**
	 * Resolve the git branch this build is being cut from by reading .git/HEAD directly (no git binary
	 * dependency, works cross-engine). Returns the branch name, or "modernization" as a sane fallback
	 * when HEAD is unreadable or detached (e.g. building from an extracted copy with no .git). The
	 * branch only influences whether tokenReplace stamps a release number ("master") or "-snapshot",
	 * so an honest fallback beats the old "development" default that could never match reality.
	 */
	private function getCurrentBranch(){
		var headFile = variables.cwd & ".git/HEAD";
		if ( !fileExists( headFile ) ) {
			return "modernization";
		}
		var head = trim( fileRead( headFile ) );
		// A normal checkout: "ref: refs/heads/<branch>" (branch may itself contain slashes).
		if ( left( head, 16 ) == "ref: refs/heads/" ) {
			return replace( head, "ref: refs/heads/", "" );
		}
		// Detached HEAD (raw SHA) carries no branch name — fall back rather than stamp a commit hash.
		return "modernization";
	}

	/**
	 * Abort the build with an accurate message when the TestBox HTTP runner is unreachable, so a build
	 * is never certified against a server that is not actually there. Kept separate from runTests() so
	 * the failure reads "runner unreachable" (start a server) rather than "tests failed" (a regression).
	 */
	private function ensureTestRunnerReachable(){
		// Probe the harness WEB ROOT, not runner.cfm itself: a bare GET of the runner EXECUTES the
		// whole test suite, which takes minutes and times this probe out (a 408 against a healthy
		// server). The root proves the server + app answer; runTests() then does the real run with
		// its own (long) timeout.
		var probeUrl   = reReplaceNoCase( variables.testRunner, "/tests/runner\.cfm.*$", "/" );
		var httpResult = "";
		try {
			cfhttp(
				url            = probeUrl,
				method         = "GET",
				timeout        = 15,
				throwonerror   = false,
				redirect       = false,
				result         = "local.httpResult"
			);
		} catch ( any e ) {
			httpResult = { statuscode : "0" };
		}
		// 2xx and 3xx both mean "server is up" (the harness root 302s to the admin).
		var statusCode = val( httpResult.statuscode ?: "0" );
		if ( statusCode < 200 || statusCode >= 400 ) {
			return error(
				"Test server unreachable at #probeUrl# (status #statusCode#). "
				& "Start a server first (box run-script start:2023) and retry. "
				& "To package source WITHOUT running tests, invoke target=buildSource explicitly."
			);
		}
	}

	/**
	 * Build Checksums
	 */
	private function buildChecksums(){
		print.greenLine( "Building checksums" ).toConsole();
		command( "checksum" )
			.params(
				path      = "#variables.exportsDir#/*.zip",
				algorithm = "SHA-512",
				extension = "sha512",
				write     = true
			)
			.run();
		command( "checksum" )
			.params(
				path      = "#variables.exportsDir#/*.zip",
				algorithm = "md5",
				extension = "md5",
				write     = true
			)
			.run();
	}

	/**
	 * DirectoryCopy is broken in lucee
	 */
	private function copy( src, target, recurse = true ){
		// process paths with excludes
		directoryList(
			src,
			false,
			"path",
			function( path ){
				var isExcluded = false;
				variables.excludes.each( function( item ){
					if ( path.replaceNoCase( variables.cwd, "", "all" ).reFindNoCase( item ) ) {
						isExcluded = true;
					}
				} );
				return !isExcluded;
			}
		).each( function( item ){
			// Copy to target
			if ( fileExists( item ) ) {
				print.blueLine( "Copying #item#" ).toConsole();
				fileCopy( item, target );
			} else {
				print.greenLine( "Copying directory #item#" ).toConsole();
				directoryCopy(
					item,
					target & "/" & item.replace( src, "" ),
					true
				);
			}
		} );
	}

	/**
	 * Gets the last Exit code to be used
	 **/
	private function getExitCode(){
		return ( createObject( "java", "java.lang.System" ).getProperty( "cfml.cli.exitCode" ) ?: 0 );
	}

	/**
	 * Ensure the export directory exists at artifacts/NAME/VERSION/
	 */
	private function ensureExportDir(
		required projectName,
		version   = "1.0.0"
	){
		if ( structKeyExists( variables, "exportsDir" ) && directoryExists( variables.exportsDir ) ){
			return;
		}
		// Prepare exports directory
		variables.exportsDir = variables.artifactsDir & "/#projectName#/#arguments.version#";
		directoryCreate( variables.exportsDir, true, true );
	}
}
