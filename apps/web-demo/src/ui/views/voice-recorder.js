// Push-to-talk voice notes: hold the mic button to record, release to send.
// MediaRecorder gives opus/webm at the lowest bitrate the browser offers,
// and the recording goes out as an encrypted attachment like a file.

import { el } from '../dom.js';
import { toast } from '../toast.js';

const MAX_RECORDING_MS = 30_000;
const MIN_RECORDING_MS = 400;
const MIME_CANDIDATES = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus', 'audio/mp4'];

function pickMime() {
  return MIME_CANDIDATES.find((mime) => typeof MediaRecorder !== 'undefined' && MediaRecorder.isTypeSupported?.(mime));
}

// attachments: src/app/services/attachments.js.
export function createVoiceRecorder({ attachments }) {
  let recording = null;

  function cleanup() {
    if (!recording) return;
    try {
      recording.stream.getTracks().forEach((track) => track.stop());
    } catch {}
    try {
      recording.indicator.remove();
    } catch {}
    recording.button?.classList.remove('recording');
    recording = null;
  }

  function cancel() {
    if (!recording) return;
    recording.canceled = true;
    if (recording.deadline) {
      clearTimeout(recording.deadline);
      recording.deadline = null;
    }
    try {
      recording.recorder.stop();
    } catch {}
    cleanup();
  }

  function stop() {
    if (!recording || recording.canceled) return;
    if (recording.recorder.state === 'inactive') return;
    // Too short to be meant: treated as a cancel.
    if (Date.now() - recording.startedAt < MIN_RECORDING_MS) {
      cancel();
      return;
    }
    if (recording.deadline) {
      clearTimeout(recording.deadline);
      recording.deadline = null;
    }
    recording.recorder.stop();
  }

  async function finalize() {
    if (!recording || recording.canceled) {
      cleanup();
      return;
    }
    const { convId, chunks } = recording;
    const mime = recording.recorder.mimeType || 'audio/webm';
    const blob = new Blob(chunks, { type: mime });
    cleanup();
    if (blob.size === 0) return;
    await attachments.sendMedia(convId, {
      kind: 'voice',
      blob,
      contentType: mime,
      failureLabel: '음성 전송 실패',
      local: { _voiceUrl: URL.createObjectURL(blob) },
    });
  }

  async function start(convId, button) {
    if (recording) return;
    if (!navigator.mediaDevices?.getUserMedia) {
      toast('이 브라우저에서 녹음 미지원', 'error');
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
      });
      const mimeType = pickMime();
      const recorder = new MediaRecorder(stream, mimeType ? { mimeType, audioBitsPerSecond: 32_000 } : undefined);
      const chunks = [];
      recorder.ondataavailable = (event) => {
        if (event.data?.size) chunks.push(event.data);
      };
      const indicator = el('div', { class: 'voice-recording-indicator' }, ['🔴 녹음 중… 손을 떼면 전송']);
      document.body.appendChild(indicator);
      button.classList.add('recording');
      recording = { convId, stream, recorder, chunks, indicator, button, startedAt: Date.now(), canceled: false, deadline: null };
      recorder.onstop = async () => finalize();
      recorder.start();
      recording.deadline = setTimeout(stop, MAX_RECORDING_MS);
    } catch (error) {
      toast('마이크 권한 필요: ' + (error.message || 'unknown'), 'error');
    }
  }

  return {
    // The mic button of a conversation's composer.
    button(convId) {
      const button = el('button', {
        class: 'voice-btn',
        'aria-label': '음성 메시지',
        title: '꾹 눌러 녹음',
        onmousedown: (event) => {
          event.preventDefault();
          start(convId, button);
        },
        onmouseup: stop,
        onmouseleave: cancel,
        ontouchstart: (event) => {
          event.preventDefault();
          start(convId, button);
        },
        ontouchend: stop,
      }, [el('span', { 'aria-hidden': 'true' }, ['🎤'])]);
      return button;
    },
  };
}
