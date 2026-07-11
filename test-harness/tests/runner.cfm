<cfsetting showDebugOutput="false">
<!---
	TestBox runner.

	Run the two directories separately — a bundle that blows up at INSTANTIATION takes down the
	whole runner request, so keeping them apart isolates the damage:

		/tests/runner.cfm?directory=tests.specs.unit
		/tests/runner.cfm?directory=tests.specs.integration

	While iterating on one file:

		/tests/runner.cfm?bundles=tests.specs.unit.RememberMeServiceSpec

	Add &reporter=text for plain-text output (handy from curl/CI).
--->
<cfparam name="url.reporter"  default="simple">
<cfparam name="url.directory" default="tests.specs">
<cfparam name="url.recurse"   default="true" type="boolean">
<cfparam name="url.bundles"   default="">
<cfparam name="url.labels"    default="">
<cfparam name="url.coverage"  default="false" type="boolean">

<cfscript>
	// Coverage is OFF by default, and that is load-bearing on Lucee 6.
	//
	// Coverage instrumentation compiles every CFML file in its path, which includes ColdBox's
	// CacheBox report skin. That skin uses the chart tag, which Lucee 6 no longer ships in core —
	// so with coverage on, EVERY run on Lucee 6 dies with "undefined tag [cfchart]" before a single
	// spec executes. Lucee 5 still bundles the tag, which is why it only breaks on 6.
	//
	// Pass &coverage=true if you genuinely want a coverage report (Lucee 5 / Adobe only).
	options = { coverage : { enabled : url.coverage } };

	// bundles and directory are mutually exclusive — passing an empty directory alongside bundles
	// makes TestBox blow up with an empty 500.
	if ( len( url.bundles ) ) {
		testbox = new testbox.system.TestBox(
			bundles  = url.bundles,
			reporter = url.reporter,
			labels   = url.labels,
			options  = options
		);
	} else {
		testbox = new testbox.system.TestBox(
			directory = { mapping : url.directory, recurse : url.recurse },
			reporter  = url.reporter,
			labels    = url.labels,
			options   = options
		);
	}

	writeOutput( testbox.run() );
</cfscript>
