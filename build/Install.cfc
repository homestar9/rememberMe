/**
 * Sets this build kit up in a project.
 *
 * Run it once, from your project root:
 *   box task run taskFile=build/Install.cfc
 *
 * It writes build/build.json, adds the release scripts to box.json, creates a changelog if you
 * do not have one, and copies RELEASE.md into your project. It never overwrites something you
 * already have unless you pass :force=true, so running it twice is safe.
 *
 * It works out sensible settings by looking at your project: the test runner comes from
 * box.json's testbox entry, and the engine list comes from the server json files in your root.
 */
component {

	/**
	 * run
	 *
	 * Sets everything up and prints what to do next.
	 *
	 * @force Overwrite files that already exist.
	 */
	function run( boolean force = false ){
		variables.buildDir = getDirectoryFromPath( getCurrentTemplatePath() );
		variables.root     = reReplace( reReplace( variables.buildDir, "[\\/]$", "" ), "[\\/][^\\/]+$", "" );

		print.line().boldLine( "Setting up the build kit" ).line( repeatString( "-", 60 ) ).toConsole();

		if ( !fileExists( variables.root & "/box.json" ) ) {
			return error(
				"No box.json found at #variables.root#. Run this from a CommandBox package: "
				& "put this build folder in your project root and run the command from there."
			);
		}

		writeBuildJSON( arguments.force );
		patchBoxJSON();
		writeChangelog( arguments.force );
		copyReleaseDoc( arguments.force );

		print
			.line( repeatString( "-", 60 ) )
			.boldGreenLine( "Done." )
			.line()
			.boldLine( "Next steps:" )
			.line( "  1. Look through build/build.json and adjust anything that is wrong." )
			.line( "  2. Check you are ready:   box run-script release:check" )
			.line( "  3. Rehearse a release:    box run-script release:dryrun" )
			.line()
			.line( "RELEASE.md in your project root explains the whole routine." )
			.toConsole();
	}

	/********************************************* STEPS *********************************************/

	/**
	 * writeBuildJSON
	 *
	 * Writes build/build.json, filling in what it can work out from the project.
	 *
	 * @force Overwrite an existing file.
	 */
	private function writeBuildJSON( required boolean force ){
		var path          = variables.buildDir & "build.json";
		var replacingSeed = fileExists( path ) && isInstallerSeed( path );
		if ( fileExists( path ) && !arguments.force && !replacingSeed ) {
			print.yellowLine( "  skip  build/build.json already exists (use :force=true to replace it)" ).toConsole();
			return;
		}

		var box         = deserializeJSON( fileRead( variables.root & "/box.json" ) );
		var projectType = detectProjectType( box );
		var settings = {
			"templateVersion" : "1.0.0",
			"projectType"     : projectType,
			"branch"          : detectBranch(),
			"changelog"       : detectChangelogName(),
			"testRunner"      : detectTestRunner( box ),
			"runTests"        : true,
			"publish"         : {
				"forgebox" : projectType == "module",
				"github"   : true
			},
			"excludes"    : defaultExcludes( projectType ),
			"excludesAdd" : [],
			"engines"     : detectEngines()
		};

		fileWrite( path, formatJSON( settings ) );
		print.greenLine( "  made  build/build.json#( replacingSeed ? " (replaced starter config)" : "" )#" ).toConsole();
		print.line( "        project type:   #settings.projectType#" ).toConsole();
		print.line( "        release branch: #settings.branch#" ).toConsole();
		print.line( "        test runner:    #settings.testRunner#" ).toConsole();
		print.line( "        engines:        #arrayLen( settings.engines )# found" ).toConsole();
	}

	/**
	 * isInstallerSeed
	 *
	 * Reports whether build.json is the starter file shipped with this kit. Only a marked
	 * starter can be replaced without force; malformed and user-owned files remain untouched.
	 *
	 * @path The build.json file to inspect.
	 */
	private boolean function isInstallerSeed( required string path ){
		try {
			var settings = deserializeJSON( fileRead( arguments.path ) );
			return isStruct( settings )
				&& isBoolean( settings._installerSeed ?: false )
				&& settings._installerSeed;
		} catch ( any e ) {
			return false;
		}
	}

	/**
	 * patchBoxJSON
	 *
	 * Adds the release scripts to box.json. Existing entries are left exactly as they are, so
	 * this cannot break scripts you already rely on.
	 */
	private function patchBoxJSON(){
		var path = variables.root & "/box.json";
		var box  = deserializeJSON( fileRead( path ) );

		if ( !structKeyExists( box, "scripts" ) ) {
			box[ "scripts" ] = {};
		}

		var wanted = {
			"release"         : "task run taskFile=build/Release.cfc target=run :version=`package show version`",
			"release:check"   : "task run taskFile=build/Doctor.cfc",
			"release:dryrun"  : "task run taskFile=build/Release.cfc target=run :version=`package show version` :dryRun=true",
			"release:existing-tag" : "task run taskFile=build/Release.cfc target=run :version=`package show version` :existingTag=true",
			"release:skip-tests" : "task run taskFile=build/Release.cfc target=run :version=`package show version` :skipTests=true",
			"release:hotfix"  : "task run taskFile=build/Release.cfc target=run :version=`package show version` :skipTests=true",
			"test:engines"    : "task run taskFile=build/TestEngines.cfc",
			"bump:major"      : "task run taskFile=build/Bump.cfc :level=major",
			"bump:minor"      : "task run taskFile=build/Bump.cfc :level=minor",
			"bump:patch"      : "task run taskFile=build/Bump.cfc :level=patch",
			"bump:prerelease" : "task run taskFile=build/Bump.cfc :level=prerelease",
			"bump:beta"       : "task run taskFile=build/Bump.cfc :level=preminor :preid=beta",
			"bump:alpha"      : "task run taskFile=build/Bump.cfc :level=preminor :preid=alpha",
			"build:package"   : "task run taskFile=build/Build.cfc :projectName=`package show slug` :version=`package show version`"
		};

		var added = [];
		var kept  = [];
		for ( var name in wanted ) {
			if ( structKeyExists( box.scripts, name ) ) {
				kept.append( name );
			} else {
				box.scripts[ name ] = wanted[ name ];
				added.append( name );
			}
		}

		if ( arrayLen( added ) ) {
			fileWrite( path, formatJSON( box ) );
			print.greenLine( "  added #arrayLen( added )# script#( arrayLen( added ) == 1 ? "" : "s" )# to box.json: #added.sort( "text" ).toList( ", " )#" ).toConsole();
		} else {
			print.yellowLine( "  skip  box.json already has every script" ).toConsole();
		}
		if ( arrayLen( kept ) ) {
			print.line( "        left alone: #kept.sort( "text" ).toList( ", " )#" ).toConsole();
		}
	}

	/**
	 * writeChangelog
	 *
	 * Creates a changelog with an [Unreleased] section when the project has none.
	 *
	 * @force Overwrite an existing changelog.
	 */
	private function writeChangelog( required boolean force ){
		var name = detectChangelogName();
		var path = variables.root & "/" & name;

		if ( fileExists( path ) && !arguments.force ) {
			print.yellowLine( "  skip  #name# already exists" ).toConsole();
			return;
		}

		var template = variables.buildDir & "templates/CHANGELOG.md";
		if ( fileExists( template ) ) {
			fileCopy( template, path );
		} else {
			fileWrite( path, defaultChangelog() );
		}
		print.greenLine( "  made  #name#" ).toConsole();
	}

	/**
	 * copyReleaseDoc
	 *
	 * Copies RELEASE.md into the project root so the routine is written down where people
	 * will find it.
	 *
	 * @force Overwrite an existing RELEASE.md.
	 */
	private function copyReleaseDoc( required boolean force ){
		var source = variables.buildDir & "templates/RELEASE.md";
		var target = variables.root & "/RELEASE.md";

		if ( !fileExists( source ) ) {
			return;
		}
		if ( fileExists( target ) && !arguments.force ) {
			print.yellowLine( "  skip  RELEASE.md already exists" ).toConsole();
			return;
		}
		fileCopy( source, target );
		print.greenLine( "  made  RELEASE.md" ).toConsole();
	}

	/********************************************* DETECTION *********************************************/

	/**
	 * detectProjectType
	 *
	 * Guesses whether this is a module or an app from box.json's type.
	 *
	 * @box The parsed box.json.
	 */
	private string function detectProjectType( required struct box ){
		var type = lCase( arguments.box.type ?: "" );
		// CommandBox package types that describe something installable rather than an app.
		return listFindNoCase( "modules,commandbox-modules,cachebox-modules,logbox-modules,wirebox-modules,plugins,interceptors", type )
			? "module"
			: "app";
	}

	/**
	 * defaultExcludes
	 *
	 * Returns the complete starter exclusion list for a new project. The list is written into
	 * build.json so an installed project keeps the packaging policy it reviewed, even when a
	 * future version of this kit changes its own defaults.
	 *
	 * Module packages omit their development toolchain and every hidden item. Applications
	 * keep files that may be part of a deployment, including modules, resources, package
	 * manifests, .htaccess, and .well-known.
	 *
	 * @projectType Either module or app.
	 */
	private array function defaultExcludes( required string projectType ){
		var common = [
			"^build$",
			"^node_modules$",
			"^test-harness$",
			"^tests$",
			"^test-results$",
			"^temp$",
			"^server(?:-.*)?\.json$",
			"^.*\.code-workspace$",
			"^(AGENTS|CLAUDE|DEVNOTES|RELEASE)\.md$",
			"\.bak$",
			"\.(zip|tar|tar\.gz|tgz|7z|rar)$"
		];

		if ( arguments.projectType == "module" ) {
			return [
				"^build$",
				"^modules$",
				"^node_modules$",
				"^resources$",
				"^test-harness$",
				"^tests$",
				"^test-results$",
				"^temp$",
				"^plans$",
				"^(package|package-lock)\.json$",
				"^webpack\.config\.js$",
				"^(vite|vitest)\.config\.js$",
				"^docker-compose\.yml$",
				"^server(?:-.*)?\.json$",
				"^.*\.code-workspace$",
				"^(AGENTS|CLAUDE|DEVNOTES|RELEASE)\.md$",
				"\.bak$",
				"\.(zip|tar|tar\.gz|tgz|7z|rar)$",
				"^\..*"
			];
		}

		// Applications may need these two hidden paths at runtime. Everything else hidden is
		// treated as local tooling or potentially sensitive configuration.
		common.append( "^\.(?!(?:htaccess|well-known)$).*" );
		return common;
	}

	/**
	 * detectBranch
	 *
	 * Uses Gitflow's configured production branch when present. Otherwise reads the current
	 * symbolic branch through git, which also works in linked worktrees, and falls back to main
	 * for a detached checkout or a folder without usable git metadata.
	 */
	private string function detectBranch(){
		try {
			var config     = new BuildConfig( variables.buildDir );
			var production = config.execNative( "git", [ "config", "--get", "gitflow.branch.master" ] );
			if ( production.exitCode == 0 && len( trim( production.output ) ) ) {
				return trim( production.output );
			}

			var current = config.execNative( "git", [ "symbolic-ref", "--quiet", "--short", "HEAD" ] );
			if ( current.exitCode == 0 && len( trim( current.output ) ) ) {
				return trim( current.output );
			}
		} catch ( any ignored ) {
			// Installation can still produce a useful starter config when git is unavailable.
		}
		return "main";
	}

	/**
	 * detectChangelogName
	 *
	 * Returns the name of the changelog the project already has, spelled exactly as it is on
	 * disk. Falls back to CHANGELOG.md, which is the usual spelling.
	 *
	 * It reads the real directory listing rather than testing names one at a time. On Windows
	 * and macOS, fileExists( "changelog.md" ) is true even when the file is really called
	 * CHANGELOG.md, so testing names would happily report a spelling that does not exist. That
	 * name then goes into build.json and works locally while failing on Linux, where the case
	 * has to match.
	 */
	private string function detectChangelogName(){
		for ( var name in directoryList( variables.root, false, "name", "*.md" ) ) {
			if ( reFindNoCase( "^changelog\.md$", name ) ) {
				return name;
			}
		}
		return "CHANGELOG.md";
	}

	/**
	 * detectTestRunner
	 *
	 * Takes the test runner URL from box.json's testbox entry, which most projects already
	 * have. Falls back to a placeholder to be corrected by hand.
	 *
	 * @box The parsed box.json.
	 */
	private string function detectTestRunner( required struct box ){
		var runner = ( arguments.box.testbox.runner ?: "" );
		if ( isArray( runner ) && arrayLen( runner ) ) {
			runner = isStruct( runner[ 1 ] ) ? ( runner[ 1 ].default ?: "" ) : runner[ 1 ];
		} else if ( isStruct( runner ) ) {
			for ( var key in runner ) {
				runner = runner[ key ];
				break;
			}
		}
		return isSimpleValue( runner ) && len( trim( runner ) )
			? trim( runner )
			: "http://127.0.0.1:60299/tests/runner.cfm";
	}

	/**
	 * detectEngines
	 *
	 * Finds the server json files in the project root and turns them into engine entries, with
	 * a readable name worked out from each file name.
	 */
	private array function detectEngines(){
		var engines = [];
		var files   = directoryList( variables.root, false, "name", "*.json" )
			.filter( function( file ){
				return reFindNoCase( "^server(?:-.*)?\.json$", file );
			} );
		files.sort( "textnocase" );

		for ( var file in files ) {
			engines.append( { "name" : engineName( file ), "configFile" : file } );
		}
		return engines;
	}

	/**
	 * engineName
	 *
	 * Prefers app.cfengine from the server file, then its name, then a readable version of the
	 * filename. A malformed file is still included so installation never silently loses a
	 * server the user expected to test.
	 *
	 * @file The server json file name.
	 */
	private string function engineName( required string file ){
		try {
			var serverSettings = deserializeJSON( fileRead( variables.root & "/" & arguments.file ) );
			if ( isStruct( serverSettings ) ) {
				var cfengine = "";
				if (
					structKeyExists( serverSettings, "app" )
					&& isStruct( serverSettings.app )
					&& structKeyExists( serverSettings.app, "cfengine" )
				) {
					cfengine = serverSettings.app.cfengine;
				}
				if ( isSimpleValue( cfengine ) && len( trim( cfengine ) ) ) {
					return readableEngineName( trim( cfengine ) );
				}

				var serverName = structKeyExists( serverSettings, "name" ) ? serverSettings.name : "";
				if ( isSimpleValue( serverName ) && len( trim( serverName ) ) ) {
					return trim( serverName );
				}
			}
		} catch ( any e ) {
			// The server command owns validation. Keep the file in the generated list and give
			// it a useful fallback name so the later error identifies the right configuration.
		}

		var name = reReplaceNoCase( arguments.file, "^server-?", "" );
		name     = reReplaceNoCase( name, "\.json$", "" );
		return len( trim( name ) ) ? readableEngineName( name ) : "Server";
	}

	/**
	 * readableEngineName
	 *
	 * Turns a value such as lucee@5 or boxlang-cfml@1 into Lucee 5 or Boxlang 1.
	 *
	 * @value A CommandBox engine ID or filename stem.
	 */
	private string function readableEngineName( required string value ){
		var name = arguments.value;
		// Drop the word that only says which language flavour it runs, so
		// server-boxlang-cfml@1.json reads as "Boxlang 1" rather than "Boxlang Cfml 1".
		name     = reReplaceNoCase( name, "[-_]cfml\b", "" );
		name     = replace( name, "@", " ", "all" );
		name     = replace( name, "-", " ", "all" );
		// Capitalise each word, so "lucee 5" reads as "Lucee 5".
		var words = listToArray( name, " " );
		for ( var i = 1; i <= arrayLen( words ); i++ ) {
			words[ i ] = uCase( left( words[ i ], 1 ) ) & mid( words[ i ], 2, len( words[ i ] ) );
		}
		return arrayToList( words, " " );
	}

	/********************************************* HELPERS *********************************************/

	/**
	 * formatJSON
	 *
	 * Turns a struct into readable JSON. CommandBox's own formatter is used when available so
	 * the result matches how it writes box.json.
	 *
	 * @data The struct to write.
	 */
	private string function formatJSON( required struct data ){
		var json = serializeJSON( arguments.data );
		try {
			return formatterUtil.formatJSON( json );
		} catch ( any e ) {
			return json;
		}
	}

	/**
	 * defaultChangelog
	 *
	 * The starter changelog, used when the templates folder is missing.
	 */
	private string function defaultChangelog(){
		var lf = chr( 10 );
		// Build the markdown headings from chr( 35 ) rather than writing hashes in the string.
		// A # starts a variable in CFML, so hashes have to be doubled, and counting them for a
		// three-hash heading is a good way to write a bug.
		var h1 = repeatString( chr( 35 ), 1 ) & " ";
		var h2 = repeatString( chr( 35 ), 2 ) & " ";
		var h3 = repeatString( chr( 35 ), 3 ) & " ";

		return h1 & "Changelog" & lf & lf
			& "All notable changes to this project are written down here." & lf & lf
			& "The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)," & lf
			& "and the version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)." & lf & lf
			& h2 & "[Unreleased]" & lf & lf
			& h3 & "Added" & lf & lf
			& "- Write your changes here as you go." & lf;
	}
}
