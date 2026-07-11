/**
 * A stand-in for the host app's user entity. Deliberately minimal — the module only ever hands
 * this object straight back to the caller and into the onRecall interception point.
 */
component accessors="true" {

	property name="id"       type="numeric";
	property name="username" type="string";

	function init( numeric id = 0, string username = "" ) {
		variables.id       = arguments.id;
		variables.username = arguments.username;
		return this;
	}

	/**
	 * The README tells consumers to call isLoaded() on whatever recallMe() returns.
	 */
	boolean function isLoaded() {
		return variables.id > 0;
	}

}
