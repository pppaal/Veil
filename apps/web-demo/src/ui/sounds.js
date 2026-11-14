// Send and receive tones, synthesized with Web Audio so no audio files ship.
// Off unless the user turns them on (nothing makes noise by default).

// isEnabled() -> whether tones play now.
export function createSounds({ isEnabled }) {
  let context = null;
  let unlocked = false;

  function audioContext() {
    if (!context) {
      try {
        context = new (window.AudioContext || window.webkitAudioContext)();
      } catch {}
    }
    return context;
  }

  // Some mobile browsers start an AudioContext only inside a user gesture,
  // and a tone for a pushed message is not one: the first click, touch or
  // key resumes it for every tone after.
  function unlockOnce() {
    if (unlocked) return;
    const ctx = audioContext();
    if (!ctx) return;
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    unlocked = true;
  }

  function play({ freq, durationMs, type = 'sine', gain = 0.04 }) {
    if (!isEnabled()) return;
    const ctx = audioContext();
    if (!ctx) return;
    const oscillator = ctx.createOscillator();
    const volume = ctx.createGain();
    oscillator.type = type;
    oscillator.frequency.value = freq;
    volume.gain.setValueAtTime(gain, ctx.currentTime);
    volume.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + durationMs / 1000);
    oscillator.connect(volume).connect(ctx.destination);
    oscillator.start();
    oscillator.stop(ctx.currentTime + durationMs / 1000);
  }

  return {
    mount() {
      for (const event of ['click', 'touchend', 'keydown']) window.addEventListener(event, unlockOnce, { once: true, capture: true });
    },
    playSend: () => play({ freq: 880, durationMs: 80, type: 'sine' }),
    playReceive: () => play({ freq: 660, durationMs: 120, type: 'triangle' }),
  };
}
