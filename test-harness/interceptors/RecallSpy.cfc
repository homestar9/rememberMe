/**
 * Records every onRecall announcement so integration specs can assert on the payload.
 *
 * Doubles as the worked example of how a consuming app listens to the module's public event:
 * declare an onRecall() method and register the interceptor. That's the whole contract.
 */
component {

	function configure() {
		variables.captured = [];
	}

	function onRecall( event, interceptData ) {
		variables.captured.append( arguments.interceptData );
	}

	array function getCaptured() {
		return variables.captured;
	}

	void function reset() {
		variables.captured = [];
	}

}
