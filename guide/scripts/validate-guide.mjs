import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateGuideModel } from './guide-model.mjs';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const guideDir = path.resolve(scriptDir, '..');
const repoDir = path.resolve(guideDir, '..');
const requireComplete = process.argv.includes('--require-complete');

const result = validateGuideModel({
  contentDir: path.join(guideDir, 'src/content/docs/components'),
  contractPath: path.join(repoDir, 'docs/covio-design-contract.json'),
  pendingPath: path.join(guideDir, 'src/content/docs/components/pending.json'),
  extensionsPath: path.join(guideDir, 'src/content/docs/components/extensions.json'),
  requireComplete,
});

if (result.errors.length) {
  for (const error of result.errors) console.error(`- ${error}`);
  process.exit(1);
}

const { summary } = result;
console.log(
  [
    'Guide model valid.',
    `contract ${summary.authoredContract}/${summary.contractTotal}`,
    `${summary.coveragePercent}%`,
    `pending ${summary.pendingContract}`,
    `extensions ${summary.extensionTotal}`,
    `surfaces ${summary.surfaceTotal}`,
    `evidence ${summary.evidenceTotal}`,
  ].join(' ')
);
