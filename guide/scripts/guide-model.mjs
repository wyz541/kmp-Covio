import fs from 'node:fs';
import path from 'node:path';
import matter from 'gray-matter';

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
    pages.push({ id: component.id, file });
  }

  const authoredIds = pages.map((page) => page.id).sort();
  const authoredIdSet = new Set(authoredIds);
  const duplicateIds = duplicates(authoredIds);
  if (duplicateIds.length) {
    errors.push(`component ids are duplicated: ${duplicateIds.join(', ')}`);
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
      coveragePercent: contractIds.length
        ? Math.round((authoredContractIds.length / contractIds.length) * 100)
        : 100,
    },
  };
}
