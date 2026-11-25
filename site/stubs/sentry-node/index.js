// An empty stand-in for @sentry/node (see package.json). Lighthouse loads @sentry/node only when
// its error reporting is on, and catches a failed load; the site's checks never turn it on.
throw new Error("@sentry/node is not installed in this project: Lighthouse error reporting stays off");
