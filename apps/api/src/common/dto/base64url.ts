import { ValidateBy, type ValidationOptions } from 'class-validator';

// The encodings device keys are published in. A key served by the directory
// must be a string every client decodes the same way.
export const BASE64URL = /^[A-Za-z0-9_-]+={0,2}$/;
export const BASE64URL_UNPADDED = /^[A-Za-z0-9_-]+$/;

/**
 * Whether the value is base64url that decodes to exactly one byte string:
 * unpadded, or padded to a multiple of four, with no leftover bits set.
 * Node's decoder accepts anything and silently drops what does not fit, so
 * without this two different strings could stand for the same key bytes.
 */
export const isCanonicalBase64Url = (value: unknown): boolean => {
  if (typeof value !== 'string' || !BASE64URL.test(value)) return false;
  const unpadded = value.replace(/=+$/, '');
  if (unpadded.length !== value.length && value.length % 4 !== 0) return false;
  return Buffer.from(unpadded, 'base64url').toString('base64url') === unpadded;
};

export const IsCanonicalBase64Url = (options?: ValidationOptions): PropertyDecorator =>
  ValidateBy(
    {
      name: 'isCanonicalBase64Url',
      validator: {
        validate: isCanonicalBase64Url,
        defaultMessage: () => '$property must be canonical base64url',
      },
    },
    options,
  );
