/// Gargosy's providers aren't tried again on an error (Riverpod 3 does by
/// default): a failure shows, with its own Retry, instead of asking RomM
/// again and again unseen. Given to the root ProviderScope and to tests'
/// containers.
Duration? noRetry(int retryCount, Object error) => null;
