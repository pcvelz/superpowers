/**
 * Tests for the visual companion's Superpowers/Prime Radiant branding.
 */

const { spawn } = require('child_process');
const http = require('http');
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const REPO_ROOT = path.join(__dirname, '../..');
const SERVER_PATH = path.join(REPO_ROOT, 'skills/brainstorming/scripts/server.cjs');
const PACKAGE_VERSION = JSON.parse(
  fs.readFileSync(path.join(REPO_ROOT, 'package.json'), 'utf-8')
).version;
const TOKEN = 'testtoken-branding-0123456789abcdef';
const ASSET_URL = 'https://primeradiant.com/brand/superpowers-visual-brainstorming-logo.png';

function cleanup(dir) {
  if (fs.existsSync(dir)) {
    fs.rmSync(dir, { recursive: true });
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function startServer({ port, dir, env = {}, serverPath = SERVER_PATH }) {
  cleanup(dir);
  return spawn('node', [serverPath], {
    env: {
      ...process.env,
      BRAINSTORM_PORT: String(port),
      BRAINSTORM_DIR: dir,
      BRAINSTORM_TOKEN: TOKEN,
      ...env
    }
  });
}

function waitForServer(server) {
  let stdout = '';
  let stderr = '';

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`Server did not start. stderr: ${stderr}`)), 5000);
    server.stdout.on('data', (data) => {
      stdout += data.toString();
      if (stdout.includes('server-started')) {
        clearTimeout(timeout);
        resolve();
      }
    });
    server.stderr.on('data', (data) => { stderr += data.toString(); });
    server.on('error', reject);
  });
}

function fetchHtml(port) {
  return new Promise((resolve, reject) => {
    const headers = { Cookie: `brainstorm-key-${port}=${TOKEN}` };
    http.get(`http://localhost:${port}/`, { headers }, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => resolve(body));
    }).on('error', reject);
  });
}

function writeFragment(dir) {
  const contentDir = path.join(dir, 'content');
  fs.mkdirSync(contentDir, { recursive: true });
  fs.writeFileSync(path.join(contentDir, 'screen.html'), '<h2>Pick a layout</h2>');
}

async function withServer(options, fn) {
  const server = startServer(options);
  try {
    await waitForServer(server);
    await fn();
  } finally {
    if (server.exitCode === null && server.signalCode === null) {
      server.kill();
      await new Promise(resolve => server.once('exit', resolve));
    }
    await sleep(100);
    cleanup(options.dir);
  }
}

let passed = 0;
let failed = 0;

async function test(name, fn) {
  try {
    await fn();
    console.log(`  PASS: ${name}`);
    passed++;
  } catch (e) {
    console.log(`  FAIL: ${name}`);
    console.log(`    ${e.message}`);
    failed++;
  }
}

function assertBrandedFallbackText(html, version = PACKAGE_VERSION) {
  assert(
    html.includes(`Prime Radiant Superpowers v${version}`),
    'disabled telemetry should keep plain text Prime Radiant/Superpowers branding'
  );
}

function assertNoRemoteLogoDefault(html, version = PACKAGE_VERSION) {
  assert(
    html.includes(`Superpowers v${version}`),
    'branding text should include dynamic package version'
  );
  assert(!html.includes('primeradiant.com'), 'default branding must not reference a remote primeradiant.com asset');
  assert(!/<img[^>]*class="brand-logo"/i.test(html), 'default branding must not render a remote logo image');
  assert(
    html.includes('<a href="https://github.com/pcvelz/superpowers">'),
    'default branding should link to the fork repository'
  );
}

async function main() {
  console.log('\n--- Visual Companion Branding ---');

  await test('framed screens render fork branding with no remote logo by default', async () => {
    const port = 3451;
    const dir = '/tmp/brainstorm-branding-default';
    await withServer({ port, dir }, async () => {
      writeFragment(dir);
      await sleep(300);
      const html = await fetchHtml(port);
      assertNoRemoteLogoDefault(html);
    });
  });

  await test('waiting screen renders fork branding with no remote logo by default', async () => {
    const port = 3452;
    const dir = '/tmp/brainstorm-branding-waiting';
    await withServer({ port, dir }, async () => {
      const html = await fetchHtml(port);
      assert(html.includes('Waiting for the agent'), 'waiting page should still render');
      assertNoRemoteLogoDefault(html);
    });
  });

  await test('SUPERPOWERS_DISABLE_TELEMETRY=true omits remote image but keeps local branding', async () => {
    const port = 3453;
    const dir = '/tmp/brainstorm-branding-disabled';
    await withServer({ port, dir, env: { SUPERPOWERS_DISABLE_TELEMETRY: 'true' } }, async () => {
      writeFragment(dir);
      await sleep(300);
      const html = await fetchHtml(port);
      assertBrandedFallbackText(html);
      assert(!html.includes(ASSET_URL), 'disabled telemetry should omit the remote image');
    });
  });

  await test('SUPERPOWERS_DISABLE_TELEMETRY=yes also omits the remote image on the waiting screen', async () => {
    const port = 3454;
    const dir = '/tmp/brainstorm-branding-disabled-waiting';
    await withServer({ port, dir, env: { SUPERPOWERS_DISABLE_TELEMETRY: 'yes' } }, async () => {
      const html = await fetchHtml(port);
      assertBrandedFallbackText(html);
      assert(!html.includes(ASSET_URL), 'disabled telemetry should omit the remote image');
    });
  });

  await test('DISABLE_TELEMETRY=true omits remote image for Claude Code telemetry opt-out', async () => {
    const port = 3455;
    const dir = '/tmp/brainstorm-branding-claude-disable-telemetry';
    await withServer({ port, dir, env: { DISABLE_TELEMETRY: 'true' } }, async () => {
      writeFragment(dir);
      await sleep(300);
      const html = await fetchHtml(port);
      assertBrandedFallbackText(html);
      assert(!html.includes(ASSET_URL), 'Claude Code telemetry opt-out should omit the remote image');
    });
  });

  await test('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 omits remote image for Claude Code traffic opt-out', async () => {
    const port = 3456;
    const dir = '/tmp/brainstorm-branding-claude-disable-nonessential';
    await withServer({ port, dir, env: { CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1' } }, async () => {
      const html = await fetchHtml(port);
      assertBrandedFallbackText(html);
      assert(!html.includes(ASSET_URL), 'Claude Code non-essential traffic opt-out should omit the remote image');
    });
  });

  console.log(`\n--- Results: ${passed} passed, ${failed} failed ---`);
  if (failed > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error('Test failed:', err);
  process.exit(1);
});
