// When the outbound queue tries a send again, and when it gives up.

const MAX_RETRY_DELAY_MS = 30_000;

// Exponential backoff after the given number of failed attempts, capped.
export const retryDelayMs = (attempts) => Math.min(MAX_RETRY_DELAY_MS, 1000 * 2 ** attempts);

// A 4xx other than 429 is a refusal no retry can turn around.
export const isPermanentRefusal = (error) => Boolean(error?.status) && error.status >= 400 && error.status < 500 && error.status !== 429;
