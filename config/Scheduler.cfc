/**
 * Module scheduler, auto-registered by ColdBox as `cbScheduler@rememberMe`.
 * No `extends` — ColdBox applies virtual inheritance from ColdBoxScheduler at load.
 */
component {

    function configure() {

        task( "rememberMe-purge-expired-tokens" )
            .call( function() {
                return getInstance( "RememberMeService@rememberMe" ).purgeExpired();
            } )
            // everyDayAt never fires at startup; every( n, "days" ) would fire immediately
            .everyDayAt( moduleSettings.purgeTime )
            // Evaluated at runtime each tick: autoPurge=false leaves the task registered but inert
            .when( function() {
                return moduleSettings.autoPurge == true;
            } )
            .onFailure( function( task, exception ) {
                log.error( "rememberMe purge task failed: #exception.message#" );
            } );

    }

}
