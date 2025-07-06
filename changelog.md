# Change Log

## 1.1.0

Added custom interception point, `onRecall`, to interceptor settings in the module configuration. This interceptor fires when the `remember().recall()` method is called, allowing for custom logic to be executed during the recall process (like logging).

## 1.0.0

Initial release.
Changed the method name for retrieving users to match the interface used by cbauth. We will now use `retrieveUserById()` instead of `getUserById()`.