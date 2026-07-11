/**
 * The harness's stand-in for a host app's user service.
 *
 * `implements` is deliberate: it makes the harness prove that the interface the module ships
 * (interfaces/IUserRememberService.cfc) is actually satisfiable, which nothing in the module
 * itself does. Wired in via moduleSettings.rememberMe.userServiceClass.
 */
component
	implements="rememberMe.interfaces.IUserRememberService"
	singleton
{

	property name="wirebox" inject="wirebox";

	/**
	 * Returns a loaded MockUser for any positive id, and an unloaded one otherwise — so specs can
	 * exercise the isLoaded() check the README tells consumers to perform.
	 */
	function retrieveUserById( required id ) {
		var userId = isValid( "integer", arguments.id ) ? javacast( "int", arguments.id ) : 0;

		return wirebox.getInstance( "MockUser" ).init(
			id       = userId,
			username = userId > 0 ? "user#userId#@example.com" : ""
		);
	}

}
