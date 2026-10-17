// Rebuild the Ash Warden's original attack sound with:
// node scripts/audio/generate_ash_warden.js
const fs = require("node:fs");
const path = require("node:path");

const RATE = 48000;
const TAU = Math.PI * 2;
const output = path.resolve(__dirname, "../../assets/audio/ash_warden");
fs.mkdirSync(output, { recursive: true });

let seed = 0xa5b0e123;
function random() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 0xffffffff * 2 - 1;
}
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));

function makeSound(seconds) {
  const count = Math.round(seconds * RATE);
  const left = new Float64Array(count);
  const right = new Float64Array(count);
  const add = (i, value, pan) => {
    if (i < 0 || i >= count) return;
    const angle = (clamp(pan, -1, 1) + 1) * Math.PI / 4;
    left[i] += value * Math.cos(angle);
    right[i] += value * Math.sin(angle);
  };

  function noise(start, duration, gain, shape, lowCut, highCut, pan = 0) {
    const first = Math.round(start * RATE);
    const size = Math.round(duration * RATE);
    let low = 0;
    let high = 0;
    const a = 1 - Math.exp(-TAU * lowCut / RATE);
    const b = 1 - Math.exp(-TAU * highCut / RATE);
    for (let j = 0; j < size; j++) {
      const t = j / RATE;
      const n = random();
      low += a * (n - low);
      high += b * (n - high);
      const fade = clamp(t / 0.006) * clamp((duration - t) / 0.025);
      add(first + j, (high - low) * gain * shape(t / duration, t) * fade, pan);
    }
  }

  function tone(start, duration, gain, from, to, decay, pan = 0, rough = 0) {
    const first = Math.round(start * RATE);
    const size = Math.round(duration * RATE);
    let phase = 0;
    for (let j = 0; j < size; j++) {
      const t = j / RATE;
      const u = t / duration;
      const frequency = from * (to / from) ** u;
      phase += TAU * frequency / RATE;
      const grit = rough * Math.sin(phase * 2.013) + rough * 0.4 * Math.sin(phase * 3.987);
      const envelope = clamp(t / 0.012) * Math.exp(-decay * t) * clamp((duration - t) / 0.06);
      add(first + j, (Math.sin(phase) + grit) * gain * envelope, pan);
    }
  }

  function bone(start, gain, pan = 0, pitch = 1) {
    const duration = 0.105;
    const first = Math.round(start * RATE);
    const size = Math.round(duration * RATE);
    let phase1 = 0;
    let phase2 = 0;
    let low = 0;
    for (let j = 0; j < size; j++) {
      const t = j / RATE;
      low += 0.18 * (random() - low);
      phase1 += TAU * (910 * pitch - 310 * t) / RATE;
      phase2 += TAU * 1490 * pitch / RATE;
      const click = (random() - low) * Math.exp(-t * 78) * 0.8;
      const wood = Math.sin(phase1) * Math.exp(-t * 44) * 0.45;
      const brittle = Math.sin(phase2) * Math.exp(-t * 55) * 0.16;
      add(first + j, (click + wood + brittle) * gain * clamp((duration - t) / 0.013), pan);
    }
  }

  function echo() {
    const dryL = left.slice();
    const dryR = right.slice();
    const taps = [[0.041, 0.16], [0.079, 0.12], [0.133, 0.085], [0.211, 0.055]];
    for (const [delay, gain] of taps) {
      const offset = Math.round(delay * RATE);
      for (let i = offset; i < count; i++) {
        left[i] += dryR[i - offset] * gain;
        right[i] += dryL[i - offset] * gain;
      }
    }
  }

  function write(name) {
    echo();
    let peak = 0;
    for (let i = 0; i < count; i++) {
      peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
    }
    const scale = 0.84 / Math.max(peak, 0.001);
    const pcm = Buffer.alloc(44 + count * 4);
    pcm.write("RIFF", 0);
    pcm.writeUInt32LE(pcm.length - 8, 4);
    pcm.write("WAVEfmt ", 8);
    pcm.writeUInt32LE(16, 16);
    pcm.writeUInt16LE(1, 20);
    pcm.writeUInt16LE(2, 22);
    pcm.writeUInt32LE(RATE, 24);
    pcm.writeUInt32LE(RATE * 4, 28);
    pcm.writeUInt16LE(4, 32);
    pcm.writeUInt16LE(16, 34);
    pcm.write("data", 36);
    pcm.writeUInt32LE(count * 4, 40);
    for (let i = 0; i < count; i++) {
      const endFade = clamp((count - i) / (RATE * 0.09));
      pcm.writeInt16LE(Math.round(clamp(left[i] * scale * endFade, -1, 1) * 32767), 44 + i * 4);
      pcm.writeInt16LE(Math.round(clamp(right[i] * scale * endFade, -1, 1) * 32767), 46 + i * 4);
    }
    fs.writeFileSync(path.join(output, `${name}.wav`), pcm);
  }
  return { noise, tone, bone, write };
}

// The hiss rises into the visible strike; brittle bone chatter rides the windup.
{
  const s = makeSound(0.92);
  s.tone(0.0, 0.52, 0.48, 62, 112, 2.3, 0, 0.35);
  s.tone(0.14, 0.55, 0.14, 370, 155, 4.5, -0.2, 0.25);
  s.noise(0.04, 0.57, 0.7, (u) => Math.sin(Math.PI * u) ** 2, 65, 2600, 0.25);
  s.noise(0.22, 0.28, 0.45, (u) => Math.sin(Math.PI * u), 1000, 7000, -0.35);
  [[0.03, 0.16, -0.5], [0.105, 0.23, 0.35], [0.19, 0.13, -0.2], [0.37, 0.28, 0.5]].forEach(([t, g, p]) => s.bone(t, g, p));
  s.write("attack");
}
