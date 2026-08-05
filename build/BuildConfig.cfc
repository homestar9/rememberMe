/**
 * Shared settings and helpers for every build task.
 *
 * Each task creates one of these first. It finds the project root, reads build/build.json,
 * fills in anything the file leaves out, and hands back one settings struct. It also owns the
 * two helpers that run outside programs (git, gh) so every task behaves the same way.
 *
 * You should not need to edit this file. Everything a project changes lives in build.json.
 */
component {

	/**
	 * init
	 *
	 * Reads and validates the settings.
	 *
	 * @buildDir The build folder holding this file. Tasks pass
	 *           getDirectoryFromPath( getCurrentTemplatePath() ).
	 */
	function init( required string buildDir ){
		variables.buildDir = reReplace( arguments.buildDir, "[\\/]$", "" );
		// The project root is one level above the build folder.
		variables.root        = reReplace( variables.buildDir, "[\\/][^\\/]+$", "" );
		variables.binaryCache = {};
		// Records which settings build.json set, so a default that depends on another setting
		// never overwrites a deliberate choice. merge() fills this in.
		variables.touchedKeys = {};
		variables.settings    = loadSettings();
		return this;
	}

	/**
	 * getSettings
	 *
	 * Returns the whole settings struct.
	 */
	struct function getSettings(){
		return variables.settings;
	}

	/**
	 * get
	 *
	 * Returns one setting.
	 *
	 * @key          The setting name, for example "branch".
	 * @defaultValue What to return when the setting is missing.
	 */
	function get( required string key, defaultValue = "" ){
		return structKeyExists( variables.settings, arguments.key ) ? variables.settings[ arguments.key ] : arguments.defaultValue;
	}

	/**
	 * repoPath
	 *
	 * Turns a path relative to the project root into a full path.
	 *
	 * Do not rename this to resolvePath. CommandBox tasks already have a resolvePath() that
	 * wins over one declared here, and it measures from the task file's folder instead of the
	 * project root, so paths come back wrong with no error to tell you.
	 *
	 * @relative A path relative to the project root, for example "CHANGELOG.md".
	 */
	string function repoPath( required string relative ){
		return variables.root & "/" & arguments.relative;
	}

	/**
	 * buildPath
	 *
	 * Turns a path relative to the build folder into a full path.
	 *
	 * @relative A path relative to the build folder, for example "templates/RELEASE.md".
	 */
	string function buildPath( required string relative ){
		return variables.buildDir & "/" & arguments.relative;
	}

	/**
	 * getRoot
	 *
	 * Returns the full path of the project root.
	 */
	string function getRoot(){
		return variables.root;
	}

	/**
	 * boxJSON
	 *
	 * Reads and returns the project's box.json.
	 */
	struct function boxJSON(){
		var path = repoPath( "box.json" );
		if ( !fileExists( path ) ) {
			throw( type = "BuildConfig", message = "No box.json found at #path#. Run build tasks from a CommandBox package." );
		}
		return deserializeJSON( fileRead( path ) );
	}

	/**
	 * slug
	 *
	 * Returns the package slug from box.json, falling back to the package name.
	 */
	string function slug(){
		var box = boxJSON();
		return box.slug ?: ( box.name ?: "package" );
	}

	/**
	 * version
	 *
	 * Returns the version from box.json.
	 */
	string function version(){
		return boxJSON().version ?: "0.0.0";
	}

	/**
	 * execNative
	 *
	 * Runs an outside program such as git or gh and returns its exit code and text output. It
	 * never throws, so the caller decides what a failure means. That matters for checks such
	 * as `git rev-parse --verify`, where a non-zero exit is the answer we want.
	 *
	 * Arguments are passed as a list rather than one long string. The program gets each one
	 * exactly as written, so a file path containing spaces needs no quoting and cannot be
	 * split in the wrong place.
	 *
	 * This runs the program directly through Java instead of through CommandBox. Task files
	 * are handed helpers such as command() and shell by CommandBox, but a plain component like
	 * this one is not, so it does its own process handling. Running directly also means no
	 * shell features: no pipes, no redirection, no wildcards. Every call here is one program
	 * with plain arguments, which is all a release needs.
	 *
	 * @name The program name, for example "git".
	 * @args The arguments, for example [ "status", "--porcelain" ].
	 */
	struct function execNative( required string name, array args = [] ){
		var binary  = findBinary( arguments.name );
		var argList = createObject( "java", "java.util.ArrayList" ).init();
		argList.add( javaCast( "string", binary ) );
		for ( var arg in arguments.args ) {
			argList.add( javaCast( "string", arg ) );
		}

		try {
			var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( argList );
			builder.directory( createObject( "java", "java.io.File" ).init( variables.root ) );
			// Fold error output into normal output. Callers show one block of text, and a
			// program's complaint is usually the most useful part of it.
			builder.redirectErrorStream( javaCast( "boolean", true ) );

			var process = builder.start();
			var reader  = createObject( "java", "java.io.BufferedReader" ).init(
				createObject( "java", "java.io.InputStreamReader" ).init( process.getInputStream() )
			);

			var output = createObject( "java", "java.lang.StringBuilder" ).init();
			var line   = reader.readLine();
			while ( !isNull( line ) ) {
				output.append( line ).append( chr( 10 ) );
				line = reader.readLine();
			}
			reader.close();

			return { exitCode : process.waitFor(), output : trim( output.toString() ) };
		} catch ( any e ) {
			// Reaching here almost always means the program is not installed. 127 is the
			// shell's own "command not found" code, so callers can spot that case.
			return {
				exitCode : 127,
				output   : "Could not run '#arguments.name#': #e.message#"
			};
		}
	}

	/**
	 * commandExists
	 *
	 * Reports whether a program can be found and run at all.
	 *
	 * @name The program name, for example "gh".
	 */
	boolean function commandExists( required string name ){
		// A found program has a full path; a missing one falls back to the bare name.
		return findBinary( arguments.name ) != arguments.name;
	}

	/**
	 * findBinary
	 *
	 * Finds a program and returns its full path, for example
	 * C:\Program Files\Git\cmd\git.exe. Returns the bare name when nothing is found, which
	 * lets the system try its own lookup and produces a readable error if the tool is missing.
	 *
	 * The path comes back without quotes. execNative() passes arguments to the program one at
	 * a time, so spaces in a path are already safe, and quotes would become part of the name.
	 *
	 * It searches PATH first, then a list of usual install folders. That second pass matters:
	 * a terminal opened before you installed a tool keeps its old PATH until you open a new
	 * one, so a program that works in a fresh window can look missing here. Searching the
	 * usual folders means a stale PATH cannot stop a release.
	 *
	 * Results are remembered for the life of the task.
	 *
	 * @name The program name, for example "git", "gh".
	 */
	string function findBinary( required string name ){
		if ( structKeyExists( variables.binaryCache, arguments.name ) ) {
			return variables.binaryCache[ arguments.name ];
		}

		var jFile     = createObject( "java", "java.io.File" );
		var separator = jFile.separator;
		var resolved  = arguments.name;
		// The empty extension covers Mac and Linux; the rest are the Windows launchers.
		var extensions = [ "", ".exe", ".cmd", ".bat" ];

		var searchDirs = [];
		var pathEnv    = createObject( "java", "java.lang.System" ).getenv( "PATH" );
		if ( !isNull( pathEnv ) ) {
			searchDirs.append( listToArray( pathEnv, jFile.pathSeparator ), true );
		}
		searchDirs.append( wellKnownDirs(), true );

		for ( var dir in searchDirs ) {
			if ( !len( trim( dir ) ) ) {
				continue;
			}
			for ( var ext in extensions ) {
				var candidate = reReplace( dir, "[\\/]$", "" ) & separator & arguments.name & ext;
				if ( fileExists( candidate ) ) {
					resolved = candidate;
					break;
				}
			}
			if ( resolved != arguments.name ) {
				break;
			}
		}

		variables.binaryCache[ arguments.name ] = resolved;
		return resolved;
	}

	/********************************************* PRIVATE HELPERS *********************************************/

	/**
	 * wellKnownDirs
	 *
	 * The usual install folders to check when PATH does not turn up a program.
	 */
	private array function wellKnownDirs(){
		var sys  = createObject( "java", "java.lang.System" );
		var dirs = [];

		var programFiles   = sys.getenv( "ProgramFiles" );
		var programFilesX86 = sys.getenv( "ProgramFiles(x86)" );
		var localAppData   = sys.getenv( "LOCALAPPDATA" );

		if ( !isNull( programFiles ) ) {
			dirs.append( programFiles & "\GitHub CLI" );
			dirs.append( programFiles & "\Git\cmd" );
			dirs.append( programFiles & "\Git\bin" );
			dirs.append( programFiles & "\nodejs" );
		}
		if ( !isNull( programFilesX86 ) ) {
			dirs.append( programFilesX86 & "\GitHub CLI" );
			dirs.append( programFilesX86 & "\Git\cmd" );
		}
		if ( !isNull( localAppData ) ) {
			dirs.append( localAppData & "\Programs\GitHub CLI" );
			dirs.append( localAppData & "\Microsoft\WinGet\Links" );
			dirs.append( localAppData & "\Programs\Git\cmd" );
		}

		// Mac and Linux.
		dirs.append( "/usr/local/bin" );
		dirs.append( "/usr/bin" );
		dirs.append( "/bin" );
		dirs.append( "/opt/homebrew/bin" );
		dirs.append( "/opt/local/bin" );
		dirs.append( "/snap/bin" );

		return dirs;
	}

	/**
	 * loadSettings
	 *
	 * Builds the settings struct: start with the defaults, lay build.json over the top, then
	 * check the result makes sense.
	 */
	private struct function loadSettings(){
		var result   = defaults();
		var jsonPath = buildPath( "build.json" );

		if ( fileExists( jsonPath ) ) {
			var raw = trim( fileRead( jsonPath ) );
			if ( len( raw ) ) {
				var userSettings = "";
				try {
					userSettings = deserializeJSON( raw );
				} catch ( any e ) {
					throw(
						type    = "BuildConfig",
						message = "build/build.json is not valid JSON (#e.message#). Two common causes: a value left unquoted, and a single backslash. Backslashes must be doubled in JSON, so a regular expression looks like ""\\.avif$""."
					);
				}
				if ( !isStruct( userSettings ) ) {
					throw( type = "BuildConfig", message = "build/build.json must hold a JSON object, for example { ""branch"": ""main"" }." );
				}
				result = merge( result, userSettings );
			}
		}

		applyProjectTypeDefaults( result );
		fillDerivedDefaults( result );
		validate( result );
		return result;
	}

	/**
	 * defaults
	 *
	 * The settings used when build.json does not say otherwise.
	 */
	private struct function defaults(){
		return {
			"templateVersion" : "1.0.0",
			"projectType"     : "module",
			"branch"          : "main",
			"changelog"       : "CHANGELOG.md",
			// Empty means "work it out": box.json's testbox.runner, or the fallback below.
			"testRunner"      : "",
			"runTests"        : true,
			"gitSync"         : true,
			"requireCleanTree": true,
			"coldboxMapping"  : "test-harness/coldbox",
			"stagingDir"      : ".tmp",
			"artifactsDir"    : ".artifacts",
			"tagPrefix"       : "v",
			"publish"         : { "forgebox" : true, "github" : true },
			"excludes"        : defaultExcludes(),
			"excludesAdd"     : [],
			"engines"         : [],
			"warmup"          : { "attempts" : 60, "delaySeconds" : 5 }
		};
	}

	/**
	 * defaultExcludes
	 *
	 * Top-level files and folders kept out of the package.
	 *
	 * Each entry is a regular expression tested against the name of every top-level item. The
	 * test is a partial match, so an entry that is the start of something you need must be
	 * anchored: a bare "modules" would also match "modules_app". Only top-level items are
	 * checked, and a folder that survives is copied whole.
	 *
	 * Add to this list with "excludesAdd" in build.json rather than replacing it.
	 */
	private array function defaultExcludes(){
		return [
			// The build tooling never ships.
			"^[\\/]?build$",
			// CommandBox reinstalls dependencies from box.json.
			"^[\\/]?modules$",
			"^[\\/]?node_modules$",
			// Tests and their harness.
			"^[\\/]?test-harness$",
			"^[\\/]?tests$",
			"^[\\/]?test-results$",
			// Server definitions and local scratch.
			"server-.*\.json",
			"^[\\/]?temp$",
			"^[\\/]?plans$",
			// Notes for people and coding agents.
			"(AGENTS|CLAUDE|DEVNOTES|RELEASE)\.md",
			"\.bak$",
			// Nothing we ship is an archive, and a stray zip can bloat a package many times over.
			"\.(zip|tar|tar\.gz|tgz|7z|rar)$",
			// Every hidden file and folder: .git, .env, .artifacts, .tmp and friends.
			"^[\\/]?\..*"
		];
	}

	/**
	 * applyProjectTypeDefaults
	 *
	 * Adjusts defaults to suit the project type. An app has nowhere to publish on ForgeBox, so
	 * that step is off unless build.json turns it back on.
	 *
	 * @settings The settings struct, changed in place.
	 */
	private void function applyProjectTypeDefaults( required struct settings ){
		// Only change the default. A build.json that names publish.forgebox itself is left
		// alone, which is what userTouched() checks.
		if ( lCase( arguments.settings.projectType ) == "app" && !userTouched( "publish.forgebox" ) ) {
			arguments.settings.publish.forgebox = false;
		}
	}

	/**
	 * fillDerivedDefaults
	 *
	 * Works out the settings that can be read from the project itself, so build.json can stay
	 * short. Right now that is the test runner URL, taken from box.json's testbox.runner.
	 *
	 * @settings The settings struct, changed in place.
	 */
	private void function fillDerivedDefaults( required struct settings ){
		if ( len( trim( arguments.settings.testRunner ) ) ) {
			return;
		}
		var box = "";
		try {
			box = boxJSON();
		} catch ( any e ) {
			box = {};
		}
		var runner = ( box.testbox.runner ?: "" );
		// testbox.runner is sometimes an array or struct of named runners. Take the first URL.
		if ( isArray( runner ) && arrayLen( runner ) ) {
			runner = isStruct( runner[ 1 ] ) ? ( runner[ 1 ].default ?: "" ) : runner[ 1 ];
		} else if ( isStruct( runner ) ) {
			for ( var key in runner ) {
				runner = runner[ key ];
				break;
			}
		}
		arguments.settings.testRunner = isSimpleValue( runner ) && len( trim( runner ) )
			? trim( runner )
			: "http://127.0.0.1:60299/tests/runner.cfm";
	}

	/**
	 * merge
	 *
	 * Lays one struct over another. Nested structs are merged key by key so a build.json that
	 * sets only publish.github keeps the default for publish.forgebox. Arrays replace whatever
	 * they land on, because a half-replaced exclude list would be a puzzle to debug.
	 *
	 * @base    The starting struct.
	 * @overlay The values to lay over it.
	 */
	private struct function merge( required struct base, required struct overlay ){
		var result = duplicate( arguments.base );
		for ( var key in arguments.overlay ) {
			var incoming = arguments.overlay[ key ];
			if (
				structKeyExists( result, key )
				&& isStruct( result[ key ] )
				&& isStruct( incoming )
			) {
				result[ key ] = merge( result[ key ], incoming );
				for ( var sub in incoming ) {
					variables.touchedKeys[ key & "." & sub ] = true;
				}
			} else {
				result[ key ] = incoming;
				variables.touchedKeys[ key ] = true;
			}
		}
		return result;
	}

	/**
	 * userTouched
	 *
	 * Reports whether build.json set a key, so defaults that depend on other settings do not
	 * overwrite a deliberate choice.
	 *
	 * @key The key, for example "publish.forgebox".
	 */
	private boolean function userTouched( required string key ){
		return structKeyExists( variables.touchedKeys ?: {}, arguments.key );
	}

	/**
	 * validate
	 *
	 * Checks the settings and explains anything that will not work. Catching it here means one
	 * clear message instead of a confusing failure later in a build.
	 *
	 * @settings The settings struct to check.
	 */
	private void function validate( required struct settings ){
		var s = arguments.settings;

		if ( !listFindNoCase( "module,app", s.projectType ) ) {
			throw( type = "BuildConfig", message = "build.json projectType must be ""module"" or ""app"", not ""#s.projectType#""." );
		}
		if ( !len( trim( s.branch ) ) ) {
			throw( type = "BuildConfig", message = "build.json branch cannot be empty. Use the branch you release from, for example ""main""." );
		}
		if ( !len( trim( s.changelog ) ) ) {
			throw( type = "BuildConfig", message = "build.json changelog cannot be empty. Name your changelog file, for example ""CHANGELOG.md""." );
		}
		if ( !isBoolean( s.runTests ) ) {
			throw( type = "BuildConfig", message = "build.json runTests must be true or false." );
		}
		if ( !isStruct( s.publish ) || !structKeyExists( s.publish, "forgebox" ) || !structKeyExists( s.publish, "github" ) ) {
			throw( type = "BuildConfig", message = "build.json publish must look like { ""forgebox"": true, ""github"": true }." );
		}
		if ( !isBoolean( s.publish.forgebox ) || !isBoolean( s.publish.github ) ) {
			throw( type = "BuildConfig", message = "build.json publish.forgebox and publish.github must be true or false." );
		}
		if ( !isArray( s.excludes ) || !isArray( s.excludesAdd ) ) {
			throw( type = "BuildConfig", message = "build.json excludes and excludesAdd must be arrays of regular expressions." );
		}
		if ( !isArray( s.engines ) ) {
			throw( type = "BuildConfig", message = "build.json engines must be an array like [ { ""name"": ""Lucee 5"", ""configFile"": ""server-lucee@5.json"" } ]." );
		}
		for ( var engine in s.engines ) {
			if ( !isStruct( engine ) || !structKeyExists( engine, "configFile" ) ) {
				throw(
					type    = "BuildConfig",
					message = "Every entry in build.json engines needs a configFile, for example { ""name"": ""Lucee 5"", ""configFile"": ""server-lucee@5.json"" }."
				);
			}
		}
		if ( !isStruct( s.warmup ) || !isNumeric( s.warmup.attempts ?: "" ) || !isNumeric( s.warmup.delaySeconds ?: "" ) ) {
			throw( type = "BuildConfig", message = "build.json warmup must look like { ""attempts"": 60, ""delaySeconds"": 5 }." );
		}
		if ( !reFindNoCase( "^https?://", s.testRunner ) ) {
			throw( type = "BuildConfig", message = "build.json testRunner must be a full URL, for example ""http://127.0.0.1:60310/tests/runner.cfm""." );
		}
	}

	/**
	 * allExcludes
	 *
	 * The exclude list the build actually uses: the base list plus anything in excludesAdd.
	 */
	array function allExcludes(){
		var result = duplicate( variables.settings.excludes );
		result.append( variables.settings.excludesAdd, true );
		return result;
	}

	/**
	 * probeUrl
	 *
	 * The address to check when asking "is the test server up?". It is the site root, not the
	 * test runner: asking for the runner would start the whole suite.
	 */
	string function probeUrl(){
		return reReplaceNoCase( variables.settings.testRunner, "^(https?://[^/]+).*$", "\1" ) & "/";
	}
}
