component {

    // The module has no required dependencies. SQLTokenStorage uses queryExecute(), which is built
    // into CFML. QBTokenStorage loads qb only when an application chooses that storage provider.
    this.title = "rememberMe";
    // Register each model in onLoad() with an explicit WireBox name.
    this.autoMapModels = false;
    // Load the remember() application helper.
	this.applicationHelper 	= [ "helpers/Mixins.cfm" ];

    function configure() {
        variables.settings = {
            userServiceClass = "",
            tokenEncryptKey = "", // Create a key with generateSecretKey("AES", 256).
            tokenEncryptAlgorithm = "aes",
            validatorHashAlgorithm = "MD5",
            days = 30,
            autoPurge = true, // Set this to false to disable the daily removal of old token rows.
            purgeGraceDays = 1, // Keep an expired row for this many days. Use 0 to remove it after expiration.
            purgeTime = "04:00", // Run the daily purge at this time in the server's time zone.
            tokenStorageClass = "SQLTokenStorage@rememberMe", // WireBox name for a provider that follows ITokenStorage.cfc.
            table = "user_remember", // Table used by the SQL and qb storage providers.
            datasource = "" // Leave this empty to use the application's default datasource.
        };

        // Register the event announced after the service recalls a user.
        variables.interceptorSettings = {
            customInterceptionPoints = [
                "onRecall"
            ]
        };
    }

    function onLoad() {
        binder.map( "RememberMeService@rememberMe" ).to( "#moduleMapping#.models.RememberMeService" );

        // Use the dependency-free SQL provider by default.
        binder.map( "SQLTokenStorage@rememberMe" ).to( "#moduleMapping#.models.SQLTokenStorage" );

        // A singleton is one shared instance. MemoryTokenStorage must use a singleton so its saved
        // tokens are still available when another service asks for the provider.
        binder
            .map( "MemoryTokenStorage@rememberMe" )
            .to( "#moduleMapping#.models.MemoryTokenStorage" )
            .asSingleton();

        // This optional provider asks WireBox for qb only after an application selects the provider.
        // The mapping can exist even when qb is not installed.
        binder.map( "QBTokenStorage@rememberMe" ).to( "#moduleMapping#.models.QBTokenStorage" );
    }

    function onUnload() {
    }

}
