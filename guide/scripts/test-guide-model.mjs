import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { validateGuideModel } from './guide-model.mjs';

function hash(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function evidenceRecord({ id, file, sha256 = hash('image') }) {
  return {
    id,
    image: `./evidence/${file}`,
    alt: '真机截图',
    capturedAt: '2026-10-21',
    device: 'MacBook Pro',
    os: 'macOS 27.0.1',
    appearance: 'light',
    scene: '测试场景',
    sourceCommit: 'abcdef1',
    sha256,
    status: 'real-device',
  };
}

function fixture({ contractIds, pending = [], extensions = [], pages = [] }) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'covio-guide-model-'));
  const contentDir = path.join(root, 'components');
  fs.mkdirSync(contentDir, { recursive: true });

  const contractComponents = Object.fromEntries(
    contractIds.map((id) => [`component/${id}`, { purpose: id }])
  );
  fs.writeFileSync(path.join(root, 'contract.json'), JSON.stringify({ components: contractComponents }));
  fs.writeFileSync(path.join(root, 'pending.json'), JSON.stringify({ components: pending }));
  fs.writeFileSync(path.join(root, 'extensions.json'), JSON.stringify({ components: extensions }));

  for (const page of pages) {
    const dir = path.join(contentDir, page.directory ?? page.id);
    fs.mkdirSync(path.join(dir, 'evidence'), { recursive: true });
    const status = page.status ? `\n  status: ${page.status}` : '';
    const evidence = page.evidence ? `\nevidence: ${JSON.stringify(page.evidence)}` : '';
    fs.writeFileSync(
      path.join(dir, 'index.mdx'),
      `---\ncomponent:\n  id: ${page.id}${status}${evidence}\n---\n`
    );
    for (const record of page.evidence ?? []) {
      fs.writeFileSync(path.join(dir, 'evidence', path.basename(record.image)), 'image');
    }
  }

  return {
    root,
    options: {
      contentDir,
      contractPath: path.join(root, 'contract.json'),
      pendingPath: path.join(root, 'pending.json'),
      extensionsPath: path.join(root, 'extensions.json'),
    },
  };
}

test('accepts an authored component and a classified pending component', () => {
  const f = fixture({ contractIds: ['button', 'card'], pending: ['card'], pages: [{ id: 'button' }] });
  const result = validateGuideModel(f.options);
  assert.deepEqual(result.errors, []);
  assert.equal(result.summary.coveragePercent, 50);
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('rejects duplicate component ids', () => {
  const f = fixture({
    contractIds: ['button'],
    pages: [
      { id: 'button', directory: 'button-a' },
      { id: 'button', directory: 'button-b' },
    ],
  });
  const result = validateGuideModel(f.options);
  assert.ok(result.errors.some((error) => error.includes('component ids are duplicated')));
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('rejects an unclassified design-contract component', () => {
  const f = fixture({ contractIds: ['button', 'card'], pending: ['card'] });
  const result = validateGuideModel(f.options);
  assert.ok(result.errors.some((error) => error.includes('unclassified')));
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('rejects authored components that remain pending', () => {
  const f = fixture({ contractIds: ['button'], pending: ['button'], pages: [{ id: 'button' }] });
  const result = validateGuideModel(f.options);
  assert.ok(result.errors.some((error) => error.includes('remain in pending.json')));
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('strict completion rejects any pending component', () => {
  const f = fixture({ contractIds: ['button'], pending: ['button'] });
  const result = validateGuideModel({ ...f.options, requireComplete: true });
  assert.ok(result.errors.some((error) => error.includes('coverage is incomplete')));
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('rejects an extension without a page', () => {
  const f = fixture({ contractIds: ['button'], pending: ['button'], extensions: [{ id: 'power-management' }] });
  const result = validateGuideModel(f.options);
  assert.ok(result.errors.some((error) => error.includes('extension components have no page')));
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('rejects a SHA-256 mismatch', () => {
  const file = '2026-10-21__device__macos-27.0.1__light__EV-BTN-001.png';
  const record = evidenceRecord({ id: 'EV-BTN-001', file, sha256: '0'.repeat(64) });
  const f = fixture({
    contractIds: ['button'],
    pages: [{ id: 'button', status: 'preview', evidence: [record] }],
  });
  const result = validateGuideModel(f.options);
  assert.ok(result.errors.some((error) => error.includes('sha256 mismatch')));
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('rejects duplicate evidence ids across component pages', () => {
  const file1 = '2026-10-21__device__macos-27.0.1__light__EV-DUP-001.png';
  const file2 = '2026-10-21__device__macos-27.0.1__dark__EV-DUP-001.png';
  const f = fixture({
    contractIds: ['button', 'card'],
    pages: [
      { id: 'button', status: 'preview', evidence: [evidenceRecord({ id: 'EV-DUP-001', file: file1 })] },
      { id: 'card', status: 'preview', evidence: [evidenceRecord({ id: 'EV-DUP-001', file: file2 })] },
    ],
  });
  const result = validateGuideModel(f.options);
  assert.ok(result.errors.some((error) => error.includes('evidence ids are duplicated')));
  fs.rmSync(f.root, { recursive: true, force: true });
});

test('rejects evidence with a missing required field', () => {
  const file = '2026-10-21__device__macos-27.0.1__light__EV-BTN-001.png';
  const record = evidenceRecord({ id: 'EV-BTN-001', file });
  delete record.scene;
  const f = fixture({
    contractIds: ['button'],
    pages: [{ id: 'button', status: 'preview', evidence: [record] }],
  });
  const result = validateGuideModel(f.options);
  assert.ok(result.errors.some((error) => error.includes('missing scene')));
  fs.rmSync(f.root, { recursive: true, force: true });
});
