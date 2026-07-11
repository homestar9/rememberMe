<cfscript>
/**
 * Shared datasource definition, included from the pseudo-constructor of BOTH
 * test-harness/Application.cfc and test-harness/tests/Application.cfc.
 *
 * Why not .cfconfig.json? The MSSQL JDBC driver class differs per engine (Adobe ships
 * DataDirect's macromedia.jdbc.MacromediaDriver; Lucee and BoxLang ship Microsoft's), and a
 * single .cfconfig.json is shared by all four server-*.json files. Defining the datasource on
 * the application lets one file serve every engine.
 *
 * Credentials come from .env, which CommandBox loads natively and passes to the server JVM.
 */
env = createObject( "java", "java.lang.System" ).getenv();

function harnessEnv( required string key, string defaultValue = "" ) {
	return ( structKeyExists( env, arguments.key ) && len( env[ arguments.key ] ) )
	 ? env[ arguments.key ]
	 : arguments.defaultValue;
}

dbHost     = harnessEnv( "DB_HOST", "127.0.0.1" );
dbPort     = harnessEnv( "DB_PORT", "1433" );
dbDatabase = harnessEnv( "DB_DATABASE", "rememberMe" );
dbUser     = harnessEnv( "DB_USER", "sa" );
dbPassword = harnessEnv( "DB_PASSWORD", "" );

if ( structKeyExists( server, "boxlang" ) ) {
	// BoxLang — requires the bx-mssql module
	this.datasources[ dbDatabase ] = {
		"driver"           : "mssql",
		"host"             : dbHost,
		"port"             : dbPort,
		"database"         : dbDatabase,
		"username"         : dbUser,
		"password"         : dbPassword,
		"custom"           : "encrypt=false&trustServerCertificate=true"
	};
} else if ( structKeyExists( server, "lucee" ) ) {
	// Lucee 5/6 — Microsoft's driver
	this.datasources[ dbDatabase ] = {
		"class"            : "com.microsoft.sqlserver.jdbc.SQLServerDriver",
		"connectionString" : "jdbc:sqlserver://#dbHost#:#dbPort#;databaseName=#dbDatabase#;encrypt=false;trustServerCertificate=true;sendStringParametersAsUnicode=false",
		"username"         : dbUser,
		"password"         : dbPassword
	};
} else {
	// Adobe 2023 — DataDirect driver, matching the shape already in .cfconfig.json
	this.datasources[ dbDatabase ] = {
		"driver"           : "MSSQLServer",
		"host"             : dbHost,
		"port"             : dbPort,
		"database"         : dbDatabase,
		"username"         : dbUser,
		"password"         : dbPassword
	};
}

this.datasource = dbDatabase;
</cfscript>
