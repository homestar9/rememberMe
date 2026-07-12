/**
 * ITokenStorage
 *
 * The contract a token storage provider must satisfy. Point the module at your implementation via
 * the `tokenStorageClass` setting (a WireBox DSL string); the default is the qb-backed
 * `QBTokenStorage@rememberMe` (models/QBTokenStorage.cfc), which is also the reference
 * implementation to copy from.
 *
 * Like IUserRememberService, this interface is documentation — the module never enforces it with
 * `implements=` (host-app components cannot reliably reference module paths, and interface
 * enforcement differs across engines). The service simply calls these methods.
 *
 * Two rules the service guarantees, so implementations can rely on them:
 *
 *  - Everything that crosses this interface is a PLAIN VALUE (strings, numerics, native dates).
 *    All crypto happens in RememberMeService before storage is involved: an implementation only
 *    ever sees the selector and the ALREADY-HASHED validator, never the raw validator, so a
 *    storage provider cannot weaken the token scheme. Query-level concerns such as cfsqltype
 *    annotations are the implementation's own business (see QBTokenStorage).
 *
 *  - `selector` arguments are never empty. The service short-circuits empty selectors itself.
 */
interface {

	/**
	 * Persist a new token row.
	 *
	 * @token A fully-formed struct: { userId, selector, hashedValidator, ipAddress, userAgent,
	 *        createdDate, modifiedDate, expirationDate }. The service computes every value —
	 *        including all dates — so storage stamps nothing of its own.
	 */
	void function create( required struct token );

	/**
	 * Fetch a token by its selector.
	 *
	 * @return A struct containing at least { userId, selector, hashedValidator, expirationDate }.
	 *         Extra keys are fine. Return an EMPTY struct when there is no match — never null.
	 */
	struct function getBySelector( required string selector );

	/**
	 * Record that a token was just used to recall a user.
	 *
	 * @selector The token's selector (unique by construction).
	 * @audit    { ipAddress, userAgent, lastUsedDate, modifiedDate } — again fully formed by the
	 *           service.
	 */
	void function updateUsage( required string selector, required struct audit );

	/**
	 * Delete the token with the given selector, if it exists.
	 */
	void function deleteBySelector( required string selector );

	/**
	 * Delete every token belonging to a user.
	 */
	void function deleteByUserId( required numeric userId );

	/**
	 * Delete every token. Used to log everyone out at once.
	 */
	void function deleteAll();

	/**
	 * Delete tokens whose expirationDate is before the cutoff. The service computes the cutoff
	 * from the purge grace period — storage just compares dates.
	 *
	 * @return The number of rows deleted, or 0 if the backend cannot report a count.
	 */
	numeric function deleteExpiredBefore( required date cutoffDate );

}
