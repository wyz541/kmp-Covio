#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';

const usage = `Usage:
  node scripts/capture-evidence.mjs --component <id> --id <EV-ID> --scene <text> [options]

Capture options:
  --input <file>        Add an existing real-device screenshot.
  --window-id <id>      Capture one macOS window with screencapture.
  Omit both             Capture an interactive screen region.

Metadata options:
  --alt <text>          Image alternative text. Defaults to the scene.
  --appearance <value>  light or dark. Defaults to the current macOS appearance.
  --status <value>      real-device (default) or preview-placeholder.
  --captured-at <date>  Date override in YYYY-MM-DD form.
  --device <text>       Device override.
  --os <text>           Operating system override.
  --source-commit <id>  Source commit override.
  --source-branch <s>   Source branch override.

File options:
  --dry-run             Print the YAML without writing or capturing.
  --overwrite           Replace an existing evidence file.
  --help                Show this message.
`;

const { values: options } = parseArgs({
  options: {
    component: { type: 'string' },
    id: { type: 'string' },
    scene: { type: 'string' },
    alt: { type: 'string' },
    input: { type: 'string' },
    'window-id': { type: 'string' },
    appearance: { type: 'string' },
    status: { type: 'string', default: 'real-device' },
    'captured-at': { type: 'string' },
    device: { type: 'string' },
    os: { type: 'string' },
    'source-commit': { type: 'string' },
    'source-branch': { type: 'string' },
    'dry-run': { type: 'boolean', default: false },
    overwrite: { type: 'boolean', default: false },
    help: { type: 'boolean', default: false },
  },
  allowPositionals: false,
});

if (options.help) {
  console.log(usage);
  process.exit(0);
}

for (const required of ['component', 'id', 'scene']) {
  if (!options[required]) {
    console.error(`Missing --${required}.\n\n${usage}`);
    process.exit(1);
  }
}

if (!/^EV-[A-Z0-9]+(?:-[A-Z0-9]+)*-\d{3}$/.test(options.id)) {
  console.error('Evidence id must look like EV-BTN-001.');
  process.exit(1);
}

if (!['real-device', 'preview-placeholder'].includes(options.status)) {
  console.error('Evidence status must be real-device or preview-placeholder.');
  process.exit(1);
}

if (options.appearance && !['light', 'dark'].includes(options.appearance)) {
  console.error('Appearance must be light or dark.');
  process.exit(1);
}

if (options.input && options['window-id']) {
  console.error('Use either --input or --window-id, not both.');
  process.exit(1);
}

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const guideDir = path.resolve(scriptDir, '..');
const repoDir = path.resolve(guideDir, '..');
const componentDir = path.join(guideDir, 'src/content/docs/components', options.component);
const evidenceDir = path.join(componentDir, 'evidence');

if (!fs.existsSync(componentDir) || !fs.statSync(componentDir).isDirectory()) {
  console.error(`Component directory does not exist: ${path.relative(guideDir, componentDir)}`);
  process.exit(1);
}

function commandText(command, args) {
  return execFileSync(command, args, { encoding: 'utf8' }).trim();
}

function currentDate() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

function currentHardware() {
  if (process.platform !== 'darwin' || options.device) return options.device;
  const hardware = JSON.parse(commandText('system_profiler', ['SPHardwareDataType', '-json']))
    .SPHardwareDataType?.[0];
  if (!hardware) throw new Error('Could not read Apple hardware information.');
  return `${hardware.machine_name} (${hardware.machine_model}, ${hardware.chip_type}, ${hardware.physical_memory})`;
}

function currentOs() {
  if (options.os) return options.os;
  if (process.platform !== 'darwin') {
    throw new Error('Use --os when capturing outside macOS.');
  }
  const version = commandText('sw_vers', ['-productVersion']);
  const build = commandText('sw_vers', ['-buildVersion']);
  return `macOS ${version} (${build})`;
}

function currentAppearance() {
  if (options.appearance) return options.appearance;
  if (process.platform !== 'darwin') return 'light';
  const result = spawnSync('defaults', ['read', '-g', 'AppleInterfaceStyle'], { encoding: 'utf8' });
  return result.status === 0 && result.stdout.trim().toLowerCase() === 'dark' ? 'dark' : 'light';
}

function gitText(args, fallback) {
  try {
    return commandText('git', ['-C', repoDir, ...args]);
  } catch {
    return fallback;
  }
}

function slug(value) {
  return value
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9.-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

const capturedAt = options['captured-at'] ?? currentDate();
if (!/^\d{4}-\d{2}-\d{2}$/.test(capturedAt)) {
  console.error('captured-at must use YYYY-MM-DD.');
  process.exit(1);
}

const device = currentHardware();
const os = currentOs();
const appearance = currentAppearance();
const sourceCommit =
  options['source-commit'] ?? gitText(['rev-parse', '--short=12', 'HEAD'], '0000000');
const sourceBranch =
  options['source-branch'] ?? gitText(['branch', '--show-current'], 'detached');

if (!device) {
  console.error('Could not determine the device. Pass --device.');
  process.exit(1);
}

if (options['dry-run'] && !options.input) {
  console.error('--dry-run requires --input so the SHA-256 can be computed.');
  process.exit(1);
}

let extension = '.png';
if (options.input) {
  const inputPath = path.resolve(options.input);
  if (!fs.existsSync(inputPath) || !fs.statSync(inputPath).isFile()) {
    console.error(`Input image does not exist: ${options.input}`);
    process.exit(1);
  }
  extension = path.extname(inputPath).toLowerCase();
  if (!['.png', '.jpg', '.jpeg', '.webp', '.heic'].includes(extension)) {
    console.error(`Unsupported image extension: ${extension}`);
    process.exit(1);
  }
}

const deviceName = device.split(' (')[0];
const osName = os.split(' (')[0];
const deviceSlug = slug(deviceName) || 'device';
const osSlug = slug(osName) || 'os';
const filename = `${capturedAt}__${deviceSlug}__${osSlug}__${appearance}__${options.id}${extension}`;
const target = path.join(evidenceDir, filename);

if (fs.existsSync(target) && !options.overwrite) {
  console.error(`Evidence file already exists: ${path.relative(guideDir, target)}`);
  console.error('Pass --overwrite only after reviewing the existing file.');
  process.exit(1);
}

if (!options['dry-run']) {
  fs.mkdirSync(evidenceDir, { recursive: true });
  if (options.input) {
    fs.copyFileSync(path.resolve(options.input), target);
  } else if (options['window-id']) {
    execFileSync('screencapture', ['-x', '-l', options['window-id'], target]);
  } else {
    console.error('Select a screen region. Press Escape to cancel.');
    execFileSync('screencapture', ['-x', '-i', target]);
  }
  if (!fs.existsSync(target) || !fs.statSync(target).isFile()) {
    console.error('Screenshot was not created. The capture may have been cancelled.');
    process.exit(1);
  }
}

const hashSource = options['dry-run'] ? path.resolve(options.input) : target;
const sha = sha256(hashSource);
const alt = options.alt ?? `Covio ${options.component} 真机实例：${options.scene}`;
const q = JSON.stringify;
const yaml = [
  '  - id: ' + q(options.id),
  '    image: ' + q('./evidence/' + filename),
  '    alt: ' + q(alt),
  '    capturedAt: ' + q(capturedAt),
  '    device: ' + q(device),
  '    os: ' + q(os),
  '    appearance: ' + q(appearance),
  '    scene: ' + q(options.scene),
  '    sourceCommit: ' + q(sourceCommit),
  '    sourceBranch: ' + q(sourceBranch),
  '    sha256: ' + q(sha),
  '    status: ' + q(options.status),
].join('\n');

if (options['dry-run']) {
  console.error(`Dry run target: ${path.relative(guideDir, target)}`);
} else {
  console.error(`Wrote ${path.relative(guideDir, target)}`);
}
console.log('\nEvidence frontmatter:\n');
console.log(yaml);
