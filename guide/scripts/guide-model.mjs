import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import matter from 'gray-matter';

const EVIDENCE_FIELDS = [
  'id',
  'image',
  'alt',
  'capturedAt',
  'device',
  'os',
  'scene',
  'sourceCommit',
  'sha256',
  'status',
];
const EVIDENCE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.heic']);
const FORMAL_COMPONENT_STATUSES = new Set(['preview', 'stable']);

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

function duplicates(values) {
  const seen = new Set();
  const repeated = new Set();
  for (const value of values) {
    if (seen.has(value)) repeated.add(value);
    seen.add(value);
  }
  return [...repeated].sort();
}

function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function evidenceDate(record) {
  if (record.capturedAt instanceof Date) {
    return record.capturedAt.toISOString().slice(0, 10);
  }
  return String(record.capturedAt ?? '').slice(0, 10);
}

function validateEvidence({ record, pageFile, componentStatus, contentDir, errors }) {
  const relativePage = path.relative(contentDir, pageFile);
  const label = `${relativePage} evidence ${record?.id ?? '<missing-id>'}`;

  for (const field of EVIDENCE_FIELDS) {
    if (record?.[field] === undefined || record?.[field] === null || record?.[field] === '') {
      errors.push(`${label} is missing ${field}`);
    }
  }

  if (typeof record?.id === 'string' && !/^EV-[A-Z0-9]+(?:-[A-Z0-9]+)*-\d{3}$/.test(record.id)) {
    errors.push(`${label} has an invalid evidence id`);
  }

  if (typeof record?.sha256 === 'string' && !/^[0-9a-f]{64}$/.test(record.sha256)) {
    errors.push(`${label} has an invalid sha256`);
  }

  if (typeof record?.sourceCommit === 'string' && !/^[0-9a-f]{7,40}$/.test(record.sourceCommit)) {
    errors.push(`${label} has an invalid sourceCommit`);
  }

  if (componentStatus === 'stable' && record?.status !== 'real-device') {
    errors.push(`${label} is not a real-device capture on a stable component`);
  }

  if (typeof record?.image !== 'string' || record.image.length === 0) return;

  const imagePath = path.resolve(path.dirname(pageFile), record.image);
  if (!fs.existsSync(imagePath) || !fs.statSync(imagePath).isFile()) {
    errors.push(`${label} image does not exist: ${record.image}`);
    return;
  }

  const evidenceDir = path.join(path.dirname(pageFile), 'evidence');
  const relativeToEvidence = path.relative(evidenceDir, imagePath);
  if (relativeToEvidence.startsWith(`..${path.sep}`) || path.isAbsolute(relativeToEvidence)) {
    errors.push(`${label} image must stay under its component evidence directory`);
  }

  const extension = path.extname(imagePath).toLowerCase();
  if (!EVIDENCE_EXTENSIONS.has(extension)) {
    errors.push(`${label} image has an unsupported extension: ${extension}`);
  }

  if (typeof record.sha256 === 'string') {
    const actualSha = sha256File(imagePath);
    if (actualSha !== record.sha256) {
      errors.push(`${label} sha256 mismatch: expected ${record.sha256}, got ${actualSha}`);
    }
  }

  const date = evidenceDate(record);
  const basename = path.basename(imagePath);
  if (date && !basename.startsWith(`${date}__`)) {
    errors.push(`${label} filename must start with capturedAt: ${date}`);
  }
  if (typeof record.id === 'string' && !basename.endsWith(`__${record.id}${extension}`)) {
    errors.push(`${label} filename must end with evidence id: ${record.id}`);
  }
}

export function validateGuideModel({
  contentDir,
  contractPath,
  pendingPath,
  extensionsPath,
  requireComplete = false,
}) {
  const errors = [];
  const contract = readJson(contractPath);
  const pendingDocument = readJson(pendingPath);
  const extensionDocument = readJson(extensionsPath);

  const contractIds = Object.keys(contract.components ?? {})
    .filter((key) => key.startsWith('component/'))
    .map((key) => key.slice('component/'.length))
    .sort();
  const contractIdSet = new Set(contractIds);

  const pendingIds = Array.isArray(pendingDocument.components)
    ? pendingDocument.components
    : [];
  const extensionEntries = Array.isArray(extensionDocument.components)
    ? extensionDocument.components
    : [];
  const extensionIds = extensionEntries.map((entry) => entry.id);

  for (const [label, values] of [
    ['pending', pendingIds],
    ['extension', extensionIds],
  ]) {
    const repeated = duplicates(values);
    if (repeated.length) errors.push(`${label} ids are duplicated: ${repeated.join(', ')}`);
  }

  const pendingUnknown = pendingIds.filter((id) => !contractIdSet.has(id));
  if (pendingUnknown.length) {
    errors.push(`pending ids are not design-contract components: ${pendingUnknown.join(', ')}`);
  }

  const componentFiles = walk(contentDir).filter(
    (file) => path.basename(file) === 'index.mdx' && path.dirname(file) !== contentDir
  );

  const pages = [];
  const evidenceIds = [];
  for (const file of componentFiles) {
    const data = matter(fs.readFileSync(file, 'utf8')).data;
    const component = data.component;
    if (!component || typeof component.id !== 'string' || component.id.length === 0) {
      errors.push(`${path.relative(contentDir, file)} is missing component.id`);
      continue;
    }

    const directoryId = path.basename(path.dirname(file));
    if (component.id !== directoryId) {
      errors.push(
        `${path.relative(contentDir, file)} uses component.id=${component.id}, expected ${directoryId}`
      );
    }

    const evidence = Array.isArray(data.evidence) ? data.evidence : [];
    if (FORMAL_COMPONENT_STATUSES.has(component.status) && evidence.length === 0) {
      errors.push(`${path.relative(contentDir, file)} has no real-device evidence`);
    }
    for (const record of evidence) {
      if (typeof record?.id === 'string') evidenceIds.push(record.id);
      validateEvidence({
        record,
        pageFile: file,
        componentStatus: component.status,
        contentDir,
        errors,
      });
    }

    pages.push({ id: component.id, file });
  }

  const authoredIds = pages.map((page) => page.id).sort();
  const authoredIdSet = new Set(authoredIds);
  const duplicateIds = duplicates(authoredIds);
  if (duplicateIds.length) {
    errors.push(`component ids are duplicated: ${duplicateIds.join(', ')}`);
  }

  const duplicateEvidenceIds = duplicates(evidenceIds);
  if (duplicateEvidenceIds.length) {
    errors.push(`evidence ids are duplicated: ${duplicateEvidenceIds.join(', ')}`);
  }

  const pendingSet = new Set(pendingIds);
  const extensionSet = new Set(extensionIds);
  const overlapPending = authoredIds.filter((id) => pendingSet.has(id));
  if (overlapPending.length) {
    errors.push(`authored components remain in pending.json: ${overlapPending.join(', ')}`);
  }

  const extensionContractOverlap = extensionIds.filter((id) => contractIdSet.has(id));
  if (extensionContractOverlap.length) {
    errors.push(`design-contract components cannot be extensions: ${extensionContractOverlap.join(', ')}`);
  }

  const unknownAuthored = authoredIds.filter(
    (id) => !contractIdSet.has(id) && !extensionSet.has(id)
  );
  if (unknownAuthored.length) {
    errors.push(`component pages are not registered: ${unknownAuthored.join(', ')}`);
  }

  const missingExtensionPages = extensionIds.filter((id) => !authoredIdSet.has(id));
  if (missingExtensionPages.length) {
    errors.push(`extension components have no page: ${missingExtensionPages.join(', ')}`);
  }

  const missingContract = contractIds.filter(
    (id) => !authoredIdSet.has(id) && !pendingSet.has(id)
  );
  if (missingContract.length) {
    errors.push(`design-contract components are unclassified: ${missingContract.join(', ')}`);
  }

  if (requireComplete && pendingIds.length > 0) {
    errors.push(`design-contract coverage is incomplete: ${pendingIds.length} components pending`);
  }

  const authoredContractIds = authoredIds.filter((id) => contractIdSet.has(id));
  return {
    errors,
    contractIds,
    pendingIds: [...pendingIds].sort(),
    authoredIds,
    authoredContractIds,
    extensionIds: [...extensionIds].sort(),
    summary: {
      contractTotal: contractIds.length,
      authoredContract: authoredContractIds.length,
      pendingContract: pendingIds.length,
      extensionTotal: extensionIds.length,
      evidenceTotal: evidenceIds.length,
      coveragePercent: contractIds.length
        ? Math.round((authoredContractIds.length / contractIds.length) * 100)
        : 100,
    },
  };
}
