// Length padding applied before AES-GCM, so a ciphertext's size reveals a
// coarse bucket rather than the plaintext length. ISO/IEC 7816-4 delimiter:
// 0x80, then 0x00 filler.
//   messages     smallest power of two from 256 B to 64 KiB, then multiples
//                of 64 KiB, that fits len + 1
//   attachments  Padmé (Nikitin et al., PETS 2019), which leaks O(log log n)
//                bits of the size with under 12% overhead

const MIN_BUCKET = 256;
const STEP_BUCKET = 65536;

function bucketFor(length) {
  let bucket = MIN_BUCKET;
  while (bucket < length && bucket < STEP_BUCKET) bucket *= 2;
  if (length <= bucket) return bucket;
  return Math.ceil(length / STEP_BUCKET) * STEP_BUCKET;
}

// E = floor(log2 L), S = floor(log2 E) + 1, rounded up to a multiple of
// 2^(E - S). Plain arithmetic, so sizes beyond 2^31 stay exact.
export function padmeLength(length) {
  if (length < 2) return length;
  const exponent = floorLog2(length);
  const step = 2 ** (exponent - (floorLog2(exponent) + 1));
  return Math.ceil(length / step) * step;
}

// Math.log2 can round up just below a power of two; correct by one step.
function floorLog2(value) {
  const estimate = Math.floor(Math.log2(value));
  return 2 ** estimate > value ? estimate - 1 : estimate;
}

function padTo(data, target) {
  if (target <= data.length) throw new RangeError('padding target must exceed the data length');
  const out = new Uint8Array(target);
  out.set(data);
  out[data.length] = 0x80;
  return out;
}

export const padMessage = (data) => padTo(data, bucketFor(data.length + 1));
export const padAttachment = (data) => padTo(data, padmeLength(data.length + 1));

// Strips the filler and exactly one 0x80. Input without a delimiter is
// returned unchanged, as the mobile reference does for unpadded legacy
// plaintext (JSON never ends in 0x00 or a bare 0x80).
export function unpad(padded) {
  let end = padded.length - 1;
  while (end >= 0 && padded[end] === 0x00) end -= 1;
  if (end < 0 || padded[end] !== 0x80) return padded.slice();
  return padded.slice(0, end);
}
