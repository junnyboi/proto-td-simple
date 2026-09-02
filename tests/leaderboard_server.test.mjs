import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawn } from 'node:child_process'
import test from 'node:test'

import {
  LeaderboardStore,
  calculateScore,
  createLeaderboardServer,
  normalizePlayerName,
} from '../server/leaderboard_server.mjs'

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')

function submission(overrides = {}) {
  return {
    submission_id: 'mission-submission-0001',
    name: '  moon!! keeper---7 ',
    stage_id: 's4',
    victory: true,
    stars: 3,
    kills: 42,
    leaks: 1,
    score_version: 1,
    ...overrides,
  }
}

function runGodotNetworkTest(baseUrl) {
  return new Promise((resolveRun, rejectRun) => {
    const runner = join(projectRoot, 'tools', 'run_godot_test.sh')
    const child = spawn(runner, ['tests/leaderboard_network_test.gd'], {
      cwd: projectRoot,
      env: {
        ...process.env,
        LEADERBOARD_TEST_URL: baseUrl,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let output = ''
    const timeout = setTimeout(() => {
      child.kill('SIGTERM')
      rejectRun(new Error(`Godot leaderboard network test timed out\n${output}`))
    }, 30_000)
    child.stdout.on('data', (chunk) => {
      output += chunk
    })
    child.stderr.on('data', (chunk) => {
      output += chunk
    })
    child.on('error', (error) => {
      clearTimeout(timeout)
      rejectRun(error)
    })
    child.on('close', (code) => {
      clearTimeout(timeout)
      if (code === 0 && output.includes('LEADERBOARD_NETWORK_TEST_OK')) {
        resolveRun(output)
      } else {
        rejectRun(new Error(`Godot leaderboard network test exited ${code}\n${output}`))
      }
    })
  })
}

test('leaderboard API, persistence, static host, and live Godot client', async (context) => {
  const temporaryRoot = mkdtempSync(join(tmpdir(), 'proto-td-leaderboard-'))
  const dataFile = join(temporaryRoot, 'server-data', 'leaderboard.json')
  const webRoot = join(temporaryRoot, 'web')
  writeFileSync(join(temporaryRoot, 'index.html'), 'outside')
  writeFileSync(join(temporaryRoot, 'secret.txt'), 'secret')
  await import('node:fs/promises').then(({ mkdir }) => mkdir(webRoot, { recursive: true }))
  writeFileSync(join(webRoot, 'index.html'), '<!doctype html><title>TD</title>')
  const { server } = createLeaderboardServer({
    dataFile,
    webRoot,
    rateLimit: { maximum: 100, windowMs: 60_000 },
    now: () => new Date('2026-09-02T05:00:00.000Z'),
  })
  await new Promise((resolveListen) => server.listen(0, '127.0.0.1', resolveListen))
  const address = server.address()
  const baseUrl = `http://127.0.0.1:${address.port}`
  context.after(async () => {
    await new Promise((resolveClose) => server.close(resolveClose))
    rmSync(temporaryRoot, { recursive: true, force: true })
  })

  await context.test('normalizes names and recomputes scores', async () => {
    assert.equal(normalizePlayerName('  moon!! keeper---7 '), 'MOON KEEPER-7')
    assert.equal(calculateScore(submission()), 2_461_600)
    const health = await fetch(`${baseUrl}/api/health`)
    assert.equal(health.status, 200)
    assert.deepEqual(await health.json(), { ok: true, score_version: 1 })
    const response = await fetch(`${baseUrl}/api/leaderboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...submission(), score: 99_999_999 }),
    })
    assert.equal(response.status, 201)
    const payload = await response.json()
    assert.equal(payload.entry.name, 'MOON KEEPER-7')
    assert.equal(payload.entry.score, 2_461_600)
    assert.equal(payload.entries[0].stage_id, 's4')
  })

  await context.test('validates, sorts, deduplicates, and persists', async () => {
    const invalid = await fetch(`${baseUrl}/api/leaderboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(submission({ submission_id: 'invalid-stage-id', stage_id: 's17' })),
    })
    assert.equal(invalid.status, 400)
    const second = await fetch(`${baseUrl}/api/leaderboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(
        submission({
          submission_id: 'mission-submission-0002',
          name: 'SECOND',
          stage_id: 's16',
          victory: false,
          stars: 0,
          kills: 0,
          leaks: 1,
        }),
      ),
    })
    assert.equal(second.status, 201)
    const duplicate = await fetch(`${baseUrl}/api/leaderboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(submission()),
    })
    assert.equal(duplicate.status, 200)
    assert.equal((await duplicate.json()).duplicate, true)
    assert.equal(existsSync(dataFile), true)
    const restored = new LeaderboardStore(dataFile)
    assert.equal(restored.list(10).length, 2)
    assert.equal(restored.list(10)[0].name, 'MOON KEEPER-7')
  })

  await context.test('serves the game without allowing traversal', async () => {
    const page = await fetch(`${baseUrl}/`)
    assert.equal(page.status, 200)
    assert.match(await page.text(), /<title>TD<\/title>/)
    assert.equal(page.headers.get('x-content-type-options'), 'nosniff')
    const traversal = await fetch(`${baseUrl}/..%2Fsecret.txt`)
    assert.equal(traversal.status, 403)
  })

  await context.test('accepts a real Godot client submission', async () => {
    await runGodotNetworkTest(baseUrl)
    const response = await fetch(`${baseUrl}/api/leaderboard?limit=20`)
    const payload = await response.json()
    assert.equal(
      payload.entries.some(
        (entry) => entry.name === 'NETWORK ACE' && entry.score === 2_340_550,
      ),
      true,
    )
  })
})
