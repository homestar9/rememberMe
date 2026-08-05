component {

    this.title = "rememberMe";
    // Don't map models, we will do it manually
    // No module dependencies, deliberately. Up to 1.4.0 this declared `[ "qb" ]` and box.json
    // installed qb into the module's own modules/ folder — which ColdBox then registered as a real
    // application-wide module, forcing a qb version onto every host app. The default storage
    // provider (models/SQLTokenStorage.cfc) now uses plain queryExecute so nothing has to be
    // installed. Do not add a dependency here without a very good reason.
    this.autoMapModels = false;
    // Helpers automatically loaded
	this.applicationHelper 	= [ "helpers/Mixins.cfm" ];

    function configure() {
        settings = {
            userServiceClass = "",
            tokenEncryptKey = "", // generateSecretKey("AES", 256);
            tokenEncryptAlgorithm = "aes",
            validatorHashAlgorithm = "MD5",
            days = 30,
            autoPurge = true, // scheduled daily purge of stale rows; set false to opt out
            purgeGraceDays = 1, // keep rows this many days past expiration; 0 = purge immediately on expiry
            purgeTime = "04:00", // daily purge run time, 24h server time
            tokenStorageClass = "SQLTokenStorage@rememberMe", // WireBox DSL of the token storage provider (see interfaces/ITokenStorage.cfc)
            table = "user_remember", // token table, used by the SQL and qb storage providers
            datasource = "" // "" = the application default datasource (the host app's Application.cfc)
        };

        // Custom Events
        interceptorSettings = {
            customInterceptionPoints = [
                "onRecall"
            ]
        };
    }

    function onLoad() {
        binder.map( "RememberMeService@rememberMe" ).to( "#moduleMapping#.models.RememberMeService" );

        // The default provider. Plain queryExecute, no dependencies.
        binder.map( "SQLTokenStorage@rememberMe" ).to( "#moduleMapping#.models.SQLTokenStorage" );

        // asSingleton, unlike everything else here. An in-memory store rebuilt on every injection
        // would start empty every time and could never recall anything.
        binder
            .map( "MemoryTokenStorage@rememberMe" )
            .to( "#moduleMapping#.models.MemoryTokenStorage" )
            .asSingleton();

        // Opt-in, and safe to map even when qb is absent: WireBox mappings are lazy, and
        // QBTokenStorage resolves qb inside getQB() rather than injecting it at build time.
        binder.map( "QBTokenStorage@rememberMe" ).to( "#moduleMapping#.models.QBTokenStorage" );
    }

    function onUnload() {
    }

}
