// Rebuild the three original Soul Steal sounds with: node scripts/audio/generate_soul_steal.js
const fs = require("node:fs");
const path = require("node:path");

const rate = 48000;
const output = path.resolve(__dirname, "../../assets/audio/soul_steal");
fs.mkdirSync(output, { recursive: true });
let seed = 0x5eedcafe;
const random = () => {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 0xffffffff * 2 - 1;
};
const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));

function write(name, seconds, synth) {
  const count = Math.ceil(seconds * rate);
  const dry = new Float64Array(count);
  const state = { low: 0, high: 0, phase: 0, chime: 0 };
  for (let i = 0; i < count; i++) {
    dry[i] = synth(i / rate, seconds, random(), state);
  }
  const delayA = Math.round(0.076 * rate);
  const delayB = Math.round(0.137 * rate);
  const wet = new Float64Array(count);
  let peak = 0;
  for (let i = 0; i < count; i++) {
    const echo = (i >= delayA ? dry[i - delayA] * 0.14 : 0)
      + (i >= delayB ? dry[i - delayB] * 0.085 : 0);
    wet[i] = Math.tanh((dry[i] + echo) * 1.45);
    peak = Math.max(peak, Math.abs(wet[i]));
  }
  const pcm = Buffer.alloc(44 + count * 2);
  pcm.write("RIFF", 0);
  pcm.writeUInt32LE(pcm.length - 8, 4);
  pcm.write("WAVEfmt ", 8);
  pcm.writeUInt32LE(16, 16);
  pcm.writeUInt16LE(1, 20);
  pcm.writeUInt16LE(1, 22);
  pcm.writeUInt32LE(rate, 24);
  pcm.writeUInt32LE(rate * 2, 28);
  pcm.writeUInt16LE(2, 32);
  pcm.writeUInt16LE(16, 34);
  pcm.write("data", 36);
  pcm.writeUInt32LE(count * 2, 40);
  const gain = 0.88 / Math.max(peak, 0.001);
  for (let i = 0; i < count; i++) {
    pcm.writeInt16LE(Math.round(clamp(wet[i] * gain, -1, 1) * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(output, name + ".wav"), pcm);
}

write("soul_cast", 0.56, (t, length, noise, s) => {
  const envelope = clamp(t / 0.035) * Math.pow(clamp(1 - t / length), 1.5);
  const cutoff = 0.018 + 0.07 * (1 - t / length);
  s.low += (noise - s.low) * cutoff;
  const rush = s.low;
  const frequency = 310 * Math.exp(-t * 3.1) + 52;
  s.phase += 2 * Math.PI * frequency / rate;
  const spectral = Math.sin(s.phase) * 0.32 + Math.sin(s.phase * 1.998) * 0.12;
  return envelope * (rush * 0.8 + spectral);
});

write("soul_travel", 0.38, (t, length, noise, s) => {
  const envelope = Math.sin(Math.PI * clamp(t / length)) ** 1.3;
  s.low += (noise - s.low) * (0.018 + 0.11 * envelope);
  s.high += (noise - s.high) * 0.003;
  const airy = s.low - s.high;
  const frequency = 680 - 500 * (t / length);
  s.phase += 2 * Math.PI * frequency / rate;
  return envelope * (airy * 1.1 + Math.sin(s.phase) * 0.17);
});

write("soul_hit", 0.72, (t, length, noise, s) => {
  const thump = Math.exp(-t * 17);
  const crack = Math.exp(-t * 42);
  s.low += (noise - s.low) * 0.13;
  s.high += (noise - s.high) * 0.012;
  s.phase += 2 * Math.PI * (52 + 132 * Math.exp(-t * 19)) / rate;
  s.chime += 2 * Math.PI * (470 + 280 * clamp(t / 0.32)) / rate;
  const lift = clamp(t / 0.045) * Math.exp(-t * 5.5);
  return Math.sin(s.phase) * thump * 0.82
    + (s.low - s.high) * crack * 0.72
    + (Math.sin(s.chime) + Math.sin(s.chime * 1.502) * 0.34) * lift * 0.22;
});
