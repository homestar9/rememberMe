/**
 * rememberMe test-harness — a ColdBox app whose only job is to load the module under
 * test and run its TestBox suite.
 */
component {

	// NOTE: no spaces. RememberMeService builds its cookie name as
	// "rememberMe-##application.applicationName##", and HTTP cookie names must be RFC 6265 tokens.
	this.name              = "rememberMe-harness";
	this.sessionManagement = true;
	this.sessionTimeout    = createTimeSpan( 0, 0, 30, 0 );
	this.setClientCookies  = true;

	// --- Mappings -------------------------------------------------------------
	COLDBOX_APP_ROOT_PATH = getDirectoryFromPath( getCurrentTemplatePath() );
	COLDBOX_APP_MAPPING   = "";
	COLDBOX_CONFIG_FILE   = "";
	COLDBOX_APP_KEY       = "";

	this.mappings[ "/root" ] = COLDBOX_APP_ROOT_PATH;
	// The repo root — lets specs invoke rememberMe.models.*, rememberMe.interfaces.*
	this.mappings[ "/rememberMe" ] = getCanonicalPath( COLDBOX_APP_ROOT_PATH & "../" );
	// The repo's PARENT — ColdBox resolves the module as "moduleroot.rememberMe".
	// See config/Coldbox.cfc afterAspectsLoad(). Requires the repo folder be named "rememberMe".
	this.mappings[ "/moduleroot" ] = getCanonicalPath( COLDBOX_APP_ROOT_PATH & "../../" );

	// Declared explicitly — see the note in tests/Application.cfc. ColdBox would add these at
	// runtime, but a mapping created mid-request isn't resolvable in that same request.
	this.mappings[ "/qb" ]          = getCanonicalPath( this.mappings[ "/rememberMe" ] & "modules/qb" );
	this.mappings[ "/cbpaginator" ] = getCanonicalPath( this.mappings[ "/qb" ] & "/modules/cbpaginator" );

	// --- Datasource -----------------------------------------------------------
	// Defined here rather than in .cfconfig.json because the MSSQL driver class differs per
	// engine and a single .cfconfig.json is shared by all four server-*.json files.
	// Credentials come from .env (loaded natively by CommandBox and inherited by the server JVM).
	include "/config/Datasource.cfm";

	public boolean function onApplicationStart() {
		application.cbBootstrap = new coldbox.system.Bootstrap(
			COLDBOX_CONFIG_FILE,
			COLDBOX_APP_ROOT_PATH,
			COLDBOX_APP_KEY,
			COLDBOX_APP_MAPPING
		);
		application.cbBootstrap.loadColdbox();
		return true;
	}

	public boolean function onRequestStart( string targetPage ) {
		if ( structKeyExists( url, "fwreinit" ) ) {
			if ( !structKeyExists( application, "cbBootstrap" ) ) {
				onApplicationStart();
			}
			application.cbBootstrap.reloadChecks();
		}
		application.cbBootstrap.onRequestStart( arguments.targetPage );
		return true;
	}

	public void function onSessionStart() {
		application.cbBootstrap.onSessionStart();
	}

	public void function onSessionEnd( struct sessionScope, struct appScope ) {
		arguments.appScope.cbBootstrap.onSessionEnd( argumentCollection = arguments );
	}

	public boolean function onMissingTemplate( template ) {
		return application.cbBootstrap.onMissingTemplate( argumentCollection = arguments );
	}

}
