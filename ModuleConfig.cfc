component {

    this.title = "rememberMe";
    // Don't map models, we will do it manually
    this.autoMapModels = false;
    // Module Dependencies
    this.dependencies = [ "qb" ];
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
            tokenStorageClass = "QBTokenStorage@rememberMe", // WireBox DSL of the token storage provider (see interfaces/ITokenStorage.cfc)
            table = "user_remember", // token table used by the default qb storage
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
        binder.map( "QBTokenStorage@rememberMe" ).to( "#moduleMapping#.models.QBTokenStorage" );
    }

    function onUnload() {
    }

}
