component {

	/**
	 * A smoke endpoint. If this renders, the harness booted and the rememberMe module registered.
	 */
	function index( event, rc, prc ) {
		var moduleLoaded = controller.getModuleService().isModuleRegistered( "rememberMe" );
		var helperFound  = structKeyExists( variables, "remember" );

		var html = "<h1>rememberMe test-harness</h1>";
		html &= "<p>Module registered: <strong>#moduleLoaded#</strong></p>";
		html &= "<p>remember() helper: <strong>#helperFound ? 'available' : 'MISSING'#</strong></p>";
		html &= "<ul>";
		html &= "<li><a href='/tests/runner.cfm?directory=tests.specs.unit'>Run unit specs</a></li>";
		html &= "<li><a href='/tests/runner.cfm?directory=tests.specs.integration'>Run integration specs</a></li>";
		html &= "</ul>";

		event.renderData( type = "html", data = html );
	}

}
