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
            days = 30
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
    }

    function onUnload() {
    }

}
