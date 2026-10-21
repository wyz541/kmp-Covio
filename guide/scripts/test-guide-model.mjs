import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { validateGuideModel } from './guide-model.mjs';

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
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, 'index.mdx'),
      `---\ncomponent:\n  id: ${page.id}\n---\n`
    );
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
