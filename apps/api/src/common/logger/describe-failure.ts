// What a log line may say about a failure: its class and its code (a Prisma
// error code, a Node errno, or a code the thrower set), in the shape
// ApiExceptionFilter logs them. Never the message: Prisma messages can quote
// query arguments, and provider responses can echo what was sent.
export const describeFailure = (error: unknown): { name: string; code: unknown } =>
  error instanceof Error
    ? { name: error.name, code: (error as { code?: unknown }).code ?? null }
    : { name: 'unknown', code: null };
