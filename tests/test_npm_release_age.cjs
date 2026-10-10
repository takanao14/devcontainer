const assert = require('node:assert/strict');
const { readFileSync, realpathSync, existsSync } = require('node:fs');
const { createRequire } = require('node:module');
const { delimiter, join } = require('node:path');
const npmPath = process.env.PATH.split(delimiter).map(dir => join(dir, 'npm')).find(existsSync);
assert.ok(npmPath, 'npm is required');
const pickManifest = createRequire(realpathSync(npmPath))('npm-pick-manifest');

const before = '2026-10-06T00:00:00Z';
const manifest = {
  name: 'release-age-fixture',
  'dist-tags': { latest: '1.2.0' },
  versions: Object.fromEntries(['1.0.0', '1.1.0', '1.2.0'].map(version =>
    [version, { name: 'release-age-fixture', version }])),
  time: {
    '1.0.0': '2026-10-05T23:59:59Z',
    '1.1.0': before,
    '1.2.0': '2026-10-06T00:00:01Z',
  },
};
assert.equal(pickManifest(manifest, 'latest', { before }).version, '1.1.0');
assert.equal(pickManifest(manifest, '^1.0.0', { before }).version, '1.1.0');
assert.throws(() => pickManifest(manifest, '1.2.0', { before }), { code: 'ETARGET' });
assert.throws(() => pickManifest(manifest, 'latest', { before: '2026-10-05T00:00:00Z' }),
  { code: 'ENOVERSIONS' });

if (process.argv.includes('--image-policy')) {
  const recorded = readFileSync('/usr/local/share/devcontainer-images/npm-before.txt', 'utf8').trim();
  assert.ok(Number.isFinite(Date.parse(recorded)));
  assert.ok(Date.now() - Date.parse(recorded) >= 2 * 24 * 60 * 60 * 1000);
  assert.equal(process.env.MISE_MINIMUM_RELEASE_AGE, '2d');
}
console.log('npm excludes young releases, accepts the cutoff boundary, and rejects unavailable pins');
