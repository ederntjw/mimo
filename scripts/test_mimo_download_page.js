#!/usr/bin/env node
// Exercise the real download page without network access or browser navigation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../docs/download/index.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const fallbackUrl = 'https://github.com/ederntjw/mimo/releases/latest';
const downloadUrl = 'https://github.com/ederntjw/mimo/releases/download/v0.8.6/Mimo-0.8.6.dmg';
const asset = { name: 'Mimo-0.8.6.dmg', browser_download_url: downloadUrl };

async function resolveRelease(release, { fail = false } = {}) {
  const elements = { status: {}, fallback: { href: fallbackUrl } };
  let destination;
  await vm.runInNewContext(script, {
    URL,
    document: { getElementById: id => elements[id] },
    window: { location: { replace: url => { destination = url; } } },
    fetch: async url => {
      assert.equal(url, 'https://api.github.com/repos/ederntjw/mimo/releases/latest');
      if (fail) throw new Error('offline');
      return { ok: true, json: async () => release };
    },
  });
  return { destination, elements };
}

test('published Mimo release opens its DMG', async () => {
  const result = await resolveRelease({ assets: [asset], draft: false, prerelease: false });
  assert.equal(result.destination, downloadUrl);
  assert.equal(result.elements.fallback.href, downloadUrl);
});

for (const [name, release] of [
  ['upstream artifact', { assets: [{ ...asset, name: 'Muesli-0.8.6.dmg' }] }],
  ['diagnostic preview', { assets: [{ ...asset, name: 'Mimo-0.8.6-preview.dmg' }] }],
  ['foreign repository', { assets: [{ ...asset, browser_download_url: 'https://github.com/Muesli-HQ/muesli/releases/download/v0.8.6/Mimo-0.8.6.dmg' }] }],
  ['foreign host', { assets: [{ ...asset, browser_download_url: 'https://example.com/ederntjw/mimo/releases/download/v0.8.6/Mimo-0.8.6.dmg' }] }],
  ['draft release', { assets: [asset], draft: true }],
  ['prerelease', { assets: [asset], prerelease: true }],
  ['missing DMG', { assets: [] }],
]) {
  test(`${name} falls back to Mimo releases`, async () => {
    const result = await resolveRelease(release);
    assert.equal(result.destination, fallbackUrl);
    assert.equal(result.elements.fallback.href, fallbackUrl);
  });
}

test('network failure retains a usable Mimo release link', async () => {
  const result = await resolveRelease(null, { fail: true });
  assert.equal(result.destination, fallbackUrl);
  assert.equal(result.elements.fallback.href, fallbackUrl);
});
