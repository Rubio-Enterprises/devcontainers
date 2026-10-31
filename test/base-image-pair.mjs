import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [modulePath, directory, baseDigest] = process.argv.slice(2);
assert.match(baseDigest, /^sha256:[a-f0-9]{64}$/);
const { validatePair } = await import(pathToFileURL(path.resolve(modulePath)));
const read = (name) => JSON.parse(fs.readFileSync(path.join(directory, name), 'utf8'));
const baseIndex = read('base-index.json');
const ciIndex = read('base-ci-index.json');
assert.equal(baseIndex.manifests.length, 2);
assert.equal(ciIndex.manifests.length, 2);

for (const arch of ['amd64', 'arm64']) {
  const select = (index) => {
    const matches = index.manifests.filter(
      (entry) => entry.platform?.os === 'linux' && entry.platform.architecture === arch,
    );
    assert.equal(matches.length, 1);
    return matches[0].digest;
  };
  assert.equal(
    select(baseIndex),
    fs.readFileSync(path.join(directory, `base-${arch}.digest`), 'utf8').trim(),
  );
  assert.equal(
    select(ciIndex),
    fs.readFileSync(path.join(directory, `base-ci-${arch}.digest`), 'utf8').trim(),
  );
  const base = read(`base-${arch}.json`);
  const ci = read(`base-ci-${arch}.json`);
  const baseConfig = read(`base-${arch}-config.json`);
  const before = read(`base-ci-${arch}-before-config.json`);
  const after = read(`base-ci-${arch}-config.json`);
  const beforeManifest = read(`base-ci-${arch}-before.json`);
  assert.deepEqual(ci.layers, beforeManifest.layers);
  assert.deepEqual(after.rootfs, before.rootfs);
  assert.equal(
    after.config.Labels['org.opencontainers.image.base.name'],
    'ghcr.io/rubio-enterprises/devcontainers/base:latest',
  );
  const expected = structuredClone(before.config);
  expected.Labels['org.opencontainers.image.base.digest'] = baseDigest;
  assert.deepEqual(after.config, expected);
  validatePair(base, ci, baseConfig, after, baseDigest, arch);
  const wrongPair = structuredClone(after);
  wrongPair.config.Labels['org.opencontainers.image.base.digest'] = select(baseIndex);
  assert.throws(
    () => validatePair(base, ci, baseConfig, wrongPair, baseDigest, arch),
    /resolved base index/,
  );
  console.log(
    `PASS: B1 validatePair linux/${arch}, index label, unchanged runtime config/layers, child-digest rejection`,
  );
}
