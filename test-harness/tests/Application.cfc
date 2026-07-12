/**
 * Application governing the TestBox runner request.
 *
 * Note this is a DIFFERENT application from test-harness/Application.cfc — it has its own
 * this.name, and therefore RememberMeService will build a different cookie name here than it does
 * when you browse the harness in a browser. That's harmless (only one app governs a given
 * request) but it will confuse you if you go looking for the cookie in devtools.
 */
component {

	// No spaces — see the note in test-harness/Application.cfc
	this.name              = "rememberMe-tests";
	this.sessionManagement = true;
	this.sessionTimeout    = createTimeSpan( 0, 0, 30, 0 );
	this.setClientCookies  = true;

	// --- Mappings -------------------------------------------------------------
	this.mappings[ "/tests" ] = getDirectoryFromPath( getCurrentTemplatePath() );
	this.mappings[ "/root" ]  = getCanonicalPath( this.mappings[ "/tests" ] & "../" );

	// The repo root — so specs can do createMock( "rememberMe.models.RememberMeService" )
	this.mappings[ "/rememberMe" ] = getCanonicalPath( this.mappings[ "/tests" ] & "../../" );
	// The repo's PARENT — ColdBox resolves the module as "moduleroot.rememberMe"
	this.mappings[ "/moduleroot" ] = getCanonicalPath( this.mappings[ "/tests" ] & "../../../" );

	// qb and its own dependency, declared explicitly rather than left to ColdBox.
	// ColdBox registers these as runtime application mappings while it loads — but a mapping
	// created mid-request is not yet resolvable for component lookups in that SAME request, so the
	// FIRST request into a cold tests app would die with "can't find component
	// [qb.models.Query.QueryBuilder]" and every request after it would pass. Declaring them here
	// means they exist before any request runs.
	// getCanonicalPath, not string concat: the paths above already end in a separator, so naive
	// concatenation yields mixed separators ("...\rememberMe\modules/qb"). Lucee tolerates that;
	// Adobe does not, and you get "Could not find the ColdFusion component qb.models.Query.QueryBuilder".
	this.mappings[ "/qb" ]          = getCanonicalPath( this.mappings[ "/rememberMe" ] & "modules/qb" );
	this.mappings[ "/cbpaginator" ] = getCanonicalPath( this.mappings[ "/qb" ] & "/modules/cbpaginator" );

	// --- Datasource (shared with the harness app) ------------------------------
	// Webroot-absolute, NOT "../config/...". Lucee 6 resolves includes against the webroot and
	// refuses to walk up out of /tests, which fails in the pseudo-constructor — i.e. before any
	// error handler exists, so you get a bare 500 with an empty body and nothing in the logs.
	include "/config/Datasource.cfm";

	function onRequestStart( required targetPage ){

		// Set a high timeout for long running tests
		setting requestTimeout="9999";
		// New ColdBox Virtual Application Starter
		request.coldBoxVirtualApp = new coldbox.system.testing.VirtualApp( appMapping = "/root" );

		// If hitting the runner or specs, prep our virtual app
		if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
			request.coldBoxVirtualApp.startup();
		}

		// ORM Reload for fresh results
		if( structKeyExists( url, "fwreinit" ) ){
			if( structKeyExists( server, "lucee" ) ){
				pagePoolClear();
			}
			// ormReload();
			request.coldBoxVirtualApp.restart();
		}

		return true;
	}

	public void function onRequestEnd( required targetPage ) {
		request.coldBoxVirtualApp.shutdown();
	}

}
