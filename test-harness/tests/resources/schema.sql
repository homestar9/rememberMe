/*
	Canonical schema for the rememberMe module (SQL Server).
	`user_remember` is the DEFAULT table name — configurable since 1.4.0 via the `table` setting,
	consumed by the default storage (models/QBTokenStorage.cfc). The harness uses the default.

	Idempotent — safe to re-run.

	NOTE on modifiedDate: it is NOT NULL and has no default, so rememberMe()'s INSERT must supply
	it. It does. Making it nullable here would let that regress silently.
*/
IF OBJECT_ID( 'user_remember', 'U' ) IS NULL
BEGIN
	CREATE TABLE user_remember (
		id              INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
		createdDate     DATETIME2     NOT NULL,
		modifiedDate    DATETIME2     NOT NULL,
		userId          INT           NOT NULL,
		selector        VARCHAR(35)   NOT NULL,   -- createUuid() is exactly 35 chars
		hashedValidator VARCHAR(32)   NOT NULL,   -- MD5 hex is exactly 32 chars
		ipAddress       VARCHAR(45)   NOT NULL,
		userAgent       VARCHAR(255)  NOT NULL,
		expirationDate  DATETIME2     NOT NULL,
		lastUsedDate    DATETIME2         NULL    -- null until the token is first recalled
	);

	CREATE INDEX IX_user_remember_selector ON user_remember ( selector );
	CREATE INDEX IX_user_remember_userId   ON user_remember ( userId );
	CREATE INDEX IX_user_remember_expirationDate ON user_remember ( expirationDate );
END

-- Outside the create-table block so databases created before 1.3.0 pick it up
IF NOT EXISTS (
	SELECT 1 FROM sys.indexes
	WHERE name = 'IX_user_remember_expirationDate' AND object_id = OBJECT_ID( 'user_remember' )
)
	CREATE INDEX IX_user_remember_expirationDate ON user_remember ( expirationDate );
