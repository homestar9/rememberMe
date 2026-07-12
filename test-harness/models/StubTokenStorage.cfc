/**
 * An in-memory token storage provider — no qb, no database, just a struct keyed by selector.
 *
 * `implements` is deliberate, exactly like MockUserService: it makes the harness prove that the
 * contract the module ships (interfaces/ITokenStorage.cfc) is actually satisfiable by a host app.
 * Wired in per-spec via moduleSettings-style override of `tokenStorageClass` — never globally in
 * the harness config, which would silently swap the storage under every other integration bundle.
 *
 * `singleton` so the spec and the service under test resolve the SAME instance and the spec can
 * assert on the stored state.
 */
component
	implements="rememberMe.interfaces.ITokenStorage"
	singleton
{

	variables.tokens = {};

	void function create( required struct token ) {
		variables.tokens[ arguments.token.selector ] = duplicate( arguments.token );
	}

	struct function getBySelector( required string selector ) {
		return structKeyExists( variables.tokens, arguments.selector )
			? duplicate( variables.tokens[ arguments.selector ] )
			: {};
	}

	void function updateUsage( required string selector, required struct audit ) {
		if ( structKeyExists( variables.tokens, arguments.selector ) ) {
			structAppend( variables.tokens[ arguments.selector ], arguments.audit, true );
		}
	}

	void function deleteBySelector( required string selector ) {
		structDelete( variables.tokens, arguments.selector );
	}

	void function deleteByUserId( required numeric userId ) {
		for ( var selector in structKeyArray( variables.tokens ) ) {
			if ( variables.tokens[ selector ].userId == arguments.userId ) {
				structDelete( variables.tokens, selector );
			}
		}
	}

	void function deleteAll() {
		variables.tokens = {};
	}

	numeric function deleteExpiredBefore( required date cutoffDate ) {
		var deleted = 0;
		for ( var selector in structKeyArray( variables.tokens ) ) {
			if ( variables.tokens[ selector ].expirationDate < arguments.cutoffDate ) {
				structDelete( variables.tokens, selector );
				deleted++;
			}
		}
		return deleted;
	}

	// --- Spec helpers (not part of the ITokenStorage contract) -------------------

	numeric function count() {
		return structCount( variables.tokens );
	}

	void function clear() {
		variables.tokens = {};
	}

}
