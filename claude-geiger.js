#!/usr/bin/env node
/**
 * claude-geiger — a Geiger counter for Claude token consumption.
 *
 * Watches Claude Code session transcripts (~/.claude/projects/** /*.jsonl)
 * and clicks like a Geiger tube as fresh tokens are burned. Cache reads are
 * treated as shielded background radiation and do not register.
 *
 * Zero dependencies. macOS audio via afplay; falls back to terminal bell.
 *
 *   node claude-geiger.js [--mute] [--dir <projects-dir>]
 */

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

// ---------------------------------------------------------------- config

const args = process.argv.slice(2);
const MUTE = args.includes('--mute');
const dirFlag = args.indexOf('--dir');
const PROJECTS_DIR =
  dirFlag !== -1 && args[dirFlag + 1]
    ? path.resolve(args[dirFlag + 1])
    : path.join(os.homedir(), '.claude', 'projects');

const SCAN_INTERVAL_MS = 1000;   // rescan for new/grown transcript files
const RENDER_INTERVAL_MS = 100;  // UI refresh
const RATE_WINDOW_MS = 15_000;   // sliding window for tokens/min
const MAX_CLICKS_PER_SEC = 30;   // tube saturation
const RATE_FLOOR = 60;           // tok/min where the gauge starts moving
const RATE_CEIL = 120_000;       // tok/min that pins the needle

const ZONES = [
  { min: 0,      label: 'BACKGROUND', color: 32 }, // green
  { min: 1_000,  label: 'ELEVATED',   color: 33 }, // yellow
  { min: 8_000,  label: 'HOT',        color: 33 },
  { min: 30_000, label: 'CRITICAL',   color: 31 }, // red
  { min: 80_000, label: 'MELTDOWN',   color: 31 },
];

// ---------------------------------------------------------------- audio

// 5ms noise-burst click, 22kHz 8-bit mono WAV, generated once into tmpdir.
function makeClickWav() {
  const sampleRate = 22050;
  const n = Math.floor(sampleRate * 0.005);
  const data = Buffer.alloc(n);
  let seed = 12345;
  for (let i = 0; i < n; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    const noise = (seed / 0x7fffffff) * 2 - 1;
    const decay = Math.exp((-6 * i) / n);
    data[i] = Math.round(128 + noise * 120 * decay);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + n, 4);
  header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate, 28);
  header.writeUInt16LE(1, 32);
  header.writeUInt16LE(8, 34); // 8-bit
  header.write('data', 36);
  header.writeUInt32LE(n, 40);
  const file = path.join(os.tmpdir(), 'claude-geiger-click.wav');
  fs.writeFileSync(file, Buffer.concat([header, data]));
  return file;
}

const clickWav = MUTE ? null : makeClickWav();
const hasAfplay = process.platform === 'darwin';
let clickFlash = 0; // frames left to show the visual click marker

function playClick() {
  clickFlash = 2;
  if (MUTE) return;
  if (hasAfplay && clickWav) {
    spawn('afplay', [clickWav], { stdio: 'ignore', detached: true }).unref();
  } else {
    process.stdout.write('\x07');
  }
}

// ---------------------------------------------------------------- transcript watching

// per-file read offsets; per-message token tally already counted
const fileOffsets = new Map();   // path -> byte offset
const countedByMsg = new Map();  // message id -> tokens already counted
const events = [];               // { t, tokens } within rate window
let totalDose = 0;               // tokens since app start
let lastBurst = null;            // { project, tokens, t }
let partialLine = new Map();     // path -> trailing partial line buffer

function freshTokens(usage) {
  if (!usage) return 0;
  return (
    (usage.input_tokens || 0) +
    (usage.cache_creation_input_tokens || 0) +
    (usage.output_tokens || 0)
  );
}

function registerTokens(tokens, project) {
  if (tokens <= 0) return;
  totalDose += tokens;
  events.push({ t: Date.now(), tokens });
  lastBurst = { project, tokens, t: Date.now() };
}

function processLine(line, project) {
  let entry;
  try {
    entry = JSON.parse(line);
  } catch {
    return;
  }
  const msg = entry && entry.message;
  if (!msg || !msg.usage) return;
  const id = msg.id || entry.requestId || entry.uuid;
  if (!id) return;
  const total = freshTokens(msg.usage);
  const prev = countedByMsg.get(id) || 0;
  if (total > prev) {
    countedByMsg.set(id, total);
    registerTokens(total - prev, project);
    // keep the dedup map bounded
    if (countedByMsg.size > 5000) {
      for (const k of countedByMsg.keys()) {
        countedByMsg.delete(k);
        if (countedByMsg.size <= 4000) break;
      }
    }
  }
}

function readAppended(file, project) {
  let stat;
  try {
    stat = fs.statSync(file);
  } catch {
    fileOffsets.delete(file);
    return;
  }
  let offset = fileOffsets.get(file);
  if (offset === undefined) {
    // first sighting: skip history, only count what happens from now on
    fileOffsets.set(file, stat.size);
    return;
  }
  if (stat.size <= offset) return;
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(stat.size - offset);
    fs.readSync(fd, buf, 0, buf.length, offset);
    fileOffsets.set(file, stat.size);
    const text = (partialLine.get(file) || '') + buf.toString('utf8');
    const lines = text.split('\n');
    partialLine.set(file, lines.pop() || '');
    for (const line of lines) if (line.trim()) processLine(line, project);
  } finally {
    fs.closeSync(fd);
  }
}

function scan() {
  let dirs;
  try {
    dirs = fs.readdirSync(PROJECTS_DIR);
  } catch {
    return;
  }
  const cutoff = Date.now() - 60 * 60 * 1000; // ignore stale sessions
  for (const d of dirs) {
    const dir = path.join(PROJECTS_DIR, d);
    let files;
    try {
      files = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const f of files) {
      if (!f.endsWith('.jsonl')) continue;
      const file = path.join(dir, f);
      let stat;
      try {
        stat = fs.statSync(file);
      } catch {
        continue;
      }
      if (stat.mtimeMs < cutoff && fileOffsets.has(file) === false) continue;
      readAppended(file, d.replace(/^-Users-[^-]+-?/, '') || d);
    }
  }
}

// ---------------------------------------------------------------- rate & clicks

function tokensPerMin() {
  const now = Date.now();
  while (events.length && events[0].t < now - RATE_WINDOW_MS) events.shift();
  const sum = events.reduce((a, e) => a + e.tokens, 0);
  return (sum / RATE_WINDOW_MS) * 60_000;
}

function zoneFor(rate) {
  let z = ZONES[0];
  for (const zone of ZONES) if (rate >= zone.min) z = zone;
  return z;
}

// 0..1 position on a log scale between RATE_FLOOR and RATE_CEIL
function gaugeFraction(rate) {
  if (rate <= RATE_FLOOR) return 0;
  const f = Math.log(rate / RATE_FLOOR) / Math.log(RATE_CEIL / RATE_FLOOR);
  return Math.min(1, f);
}

// Poisson click scheduler: exponential gaps, rate tied to the gauge
let nextClickAt = 0;
function scheduleClicks() {
  const frac = gaugeFraction(tokensPerMin());
  if (frac <= 0) {
    // background: occasional lonely click, like cosmic rays
    if (Math.random() < 0.003) playClick();
    return;
  }
  const cps = 0.5 + frac * frac * MAX_CLICKS_PER_SEC;
  const now = Date.now();
  if (now >= nextClickAt) {
    playClick();
    const gap = -Math.log(1 - Math.random()) / cps; // exponential, seconds
    nextClickAt = now + Math.max(15, gap * 1000);
  }
}

// ---------------------------------------------------------------- UI

const ESC = '\x1b[';
function color(c, s) {
  return `${ESC}${c}m${s}${ESC}0m`;
}

function fmt(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(2) + ' Mtok';
  if (n >= 1_000) return (n / 1_000).toFixed(1) + ' ktok';
  return Math.round(n) + ' tok';
}

const GAUGE_WIDTH = 50;
function gaugeBar(frac, zoneColor) {
  const filled = Math.round(frac * GAUGE_WIDTH);
  const bar =
    color(zoneColor, '▮'.repeat(filled)) +
    color(90, '▯'.repeat(GAUGE_WIDTH - filled));
  return bar;
}

let started = Date.now();

function render() {
  const rate = tokensPerMin();
  const zone = zoneFor(rate);
  const frac = gaugeFraction(rate);
  const click = clickFlash > 0 ? color(33, ' ⚡CLICK') : '        ';
  if (clickFlash > 0) clickFlash--;

  const uptime = Math.floor((Date.now() - started) / 1000);
  const hh = String(Math.floor(uptime / 3600)).padStart(2, '0');
  const mm = String(Math.floor((uptime % 3600) / 60)).padStart(2, '0');
  const ss = String(uptime % 60).padStart(2, '0');

  const burst =
    lastBurst && Date.now() - lastBurst.t < 30_000
      ? `+${fmt(lastBurst.tokens)}  ${lastBurst.project.slice(0, 30)}`
      : '—';

  const lines = [
    '',
    color(1, '   ☢  CLAUDE GEIGER ') + color(90, `· dosimeter for token exposure`),
    '',
    `   ${gaugeBar(frac, zone.color)}${click}`,
    '',
    `   RATE  ${color(1, fmt(rate).padEnd(12))}/min     ZONE  ${color(zone.color, zone.label)}`,
    `   DOSE  ${color(1, fmt(totalDose).padEnd(12))}        UPTIME  ${hh}:${mm}:${ss}`,
    `   LAST  ${burst}`,
    '',
    color(90, '   cache reads shielded · ctrl-c to evacuate'),
    '',
  ];

  // repaint in place
  process.stdout.write(ESC + 'H' + ESC + 'J' + lines.join('\n'));
}

// ---------------------------------------------------------------- main

if (!fs.existsSync(PROJECTS_DIR)) {
  console.error(`No transcripts directory at ${PROJECTS_DIR}`);
  process.exit(1);
}

process.stdout.write(ESC + '2J' + ESC + '?25l'); // clear, hide cursor
function cleanup() {
  process.stdout.write(ESC + '?25h' + '\n');
  process.exit(0);
}
process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);

scan(); // prime offsets at EOF
setInterval(scan, SCAN_INTERVAL_MS);
setInterval(scheduleClicks, 20);
setInterval(render, RENDER_INTERVAL_MS);
