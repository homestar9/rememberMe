component {

	function configure() {
		coldbox = {
			appName                 : "rememberMe-harness",
			handlerCaching          : false,
			eventCaching            : false,
			viewCaching             : false,
			reinitPassword          : "",
			handlersIndexAutoReload : true,
			// Off deliberately. With debugMode on, ColdBox compiles its CacheBox report skin, which
			// uses the cfchart tag — and Lucee 6 no longer ships cfchart in core, so every request
			// dies with "undefined tag [cfchart]". A test harness has no use for the debugger.
			// (Do not write that tag name in angle brackets anywhere in this file: Lucee 6's parser
			// picks it up even inside a comment, which reproduces the very error described above.)
			debugMode               : false,
			debugPassword           : "",
			defaultEvent            : "Main.index",
			requestStartHandler     : "",
			invalidEventHandler     : "",
			customErrorTemplate     : "/coldbox/system/exceptions/Whoops.cfm"
		};

		moduleSettings = {
			// qb is the HARNESS's dependency, not the module's — rememberMe stopped depending on it
			// in 2.0.0. It is installed here only so the QBTokenStorage specs have something to run
			// against; the module's own default provider is SQLTokenStorage, which needs nothing.
			//
			// Pin the grammar rather than letting AutoDiscover sniff the connection. The harness
			// runs on SQL Server, which is what the module documents and ships against.
			// No datasource here on purpose: Application.cfc sets `this.datasource`, so qb
			// inherits the application default and the name stays in one place (.env).
			qb : { defaultGrammar : "SqlServerGrammar@qb" },

			// Note what is NOT overridden below: tokenStorageClass, table, datasource and the purge
			// settings. ModuleSpec asserts those as the module's own defaults, so setting one here
			// would quietly turn that assertion into a tautology.
			rememberMe : {
				userServiceClass       : "MockUserService",
				tokenEncryptKey        : "HpNHIyWJc0AYCslJ+W0ye9P6eCxVvv5nQiuoKw99uQc=",
				tokenEncryptAlgorithm  : "aes",
				validatorHashAlgorithm : "MD5",
				days                   : 30
			}
		};

		logBox = {
			appenders : {
				console : { class : "coldbox.system.logging.appenders.ConsoleAppender" }
			},
			root : { levelmax : "INFO", appenders : "*" }
		};
	}

	/**
	 * Register the module under test.
	 *
	 * afterAspectsLoad, and not somewhere earlier, for the two reasons spelled out on the calls
	 * below: `remember()` needs the helper pass re-announced, and RecallSpy has to be registered
	 * after the module so it can bind to the custom `onRecall` point. Both still apply.
	 *
	 * (Before 2.0.0 there was a third reason — waiting for the module's own modules/qb to register
	 * so `this.dependencies = [ "qb" ]` could resolve. The module has no dependencies now, but the
	 * other two reasons are enough on their own, so this stays where it is.)
	 *
	 * "moduleroot" is the CFC-invocation mapping declared in Application.cfc, pointing at the
	 * PARENT of the repo — so ColdBox finds the module at /moduleroot/rememberMe.
	 */
	function afterAspectsLoad( event, interceptData, rc, prc ) {
		controller
			.getModuleService()
			.registerAndActivateModule( moduleName = "rememberMe", invocationPath = "moduleroot" );

		controller.getRenderer().startup();

		// REQUIRED. The module ships `this.applicationHelper = [ "helpers/Mixins.cfm" ]`, which is
		// what provides the remember() helper. Because the module is registered late, ColdBox's
		// helper-injection pass has already run — without re-announcing, remember() silently
		// does not exist. (Almost certainly the README's "Known Issues" note about `remember`
		// being unresolvable on first load.)
		controller.getInterceptorService().announce( "cbLoadInterceptorHelpers" );

		// Registered AFTER the module, deliberately. ColdBox binds an interceptor's methods to
		// interception points at REGISTRATION time, and `onRecall` is a custom point that only
		// exists once rememberMe has registered. Declare this spy in the `interceptors` config
		// array instead and its onRecall() is silently never bound — the announcement fires and
		// nothing hears it.
		controller
			.getInterceptorService()
			.registerInterceptor( interceptorClass = "interceptors.RecallSpy", interceptorName = "RecallSpy" );
	}

}
