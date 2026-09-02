import { createReadStream, existsSync, mkdirSync, readFileSync } from 'node:fs'
import { rename, writeFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { dirname, extname, isAbsolute, resolve, sep } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

export const SCORE_VERSION = 1
export const DEFAULT_LIMIT = 10
export const MAX_LIMIT = 20
export const MAX_RECORDS = 1000
export const MAX_KILLS = 500
export const MAX_LEAKS = 100

const JSON_HEADERS = { 'Content-Type': 'application/json; charset=utf-8' }
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.ogg': 'audio/ogg',
  '.wav': 'audio/wav',
  '.svg': 'image/svg+xml; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
}

export function missionNumber(stageId) {
  const match = /^s([1-9]|10)$/.exec(String(stageId ?? ''))
  return match ? Number.parseInt(match[1], 10) : 0
}

export function calculateScore(mission) {
  return Math.max(
    0,
    (mission.victory ? 2_000_000 : 0) +
      missionNumber(mission.stage_id) * 100_000 +
      mission.stars * 20_000 +
      mission.kills * 50 -
      mission.leaks * 500,
  )
}

export function normalizePlayerName(value) {
  let result = ''
  let previousSpace = false
  let previousHyphen = false
  for (const rawCharacter of String(value ?? '').toUpperCase()) {
    const character = rawCharacter
    if (character === ' ') {
      if (result && !previousSpace) result += character
      previousSpace = true
      previousHyphen = false
    } else if (character === '-') {
      if (result && !previousHyphen) result += character
      previousSpace = false
      previousHyphen = true
    } else if (character === '_' || /[A-Z0-9]/.test(character)) {
      result += character
      previousSpace = false
      previousHyphen = false
    }
    if (result.length >= 16) break
  }
  result = result.trim().replace(/-$/, '')
  return result || 'COMMANDER'
}

function integerField(body, name, minimum, maximum) {
  const value = body[name]
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RequestError(400, `${name} must be an integer from ${minimum} to ${maximum}`)
  }
  return value
}

export function validateSubmission(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new RequestError(400, 'request body must be a JSON object')
  }
  if (body.score_version !== SCORE_VERSION) {
    throw new RequestError(400, `score_version must be ${SCORE_VERSION}`)
  }
  if (
    typeof body.submission_id !== 'string' ||
    !/^[A-Za-z0-9_-]{8,96}$/.test(body.submission_id)
  ) {
    throw new RequestError(
      400,
      'submission_id must contain 8-96 letters, numbers, underscores, or hyphens',
    )
  }
  if (typeof body.victory !== 'boolean') {
    throw new RequestError(400, 'victory must be a boolean')
  }
  const stageId = String(body.stage_id ?? '')
  if (missionNumber(stageId) === 0) {
    throw new RequestError(400, 'stage_id must be s1 through s10')
  }
  return {
    submission_id: body.submission_id,
    name: normalizePlayerName(body.name),
    stage_id: stageId,
    victory: body.victory,
    stars: integerField(body, 'stars', 0, 3),
    kills: integerField(body, 'kills', 0, MAX_KILLS),
    leaks: integerField(body, 'leaks', 0, MAX_LEAKS),
    score_version: SCORE_VERSION,
  }
}

function compareRecords(left, right) {
  return (
    right.score - left.score ||
    String(left.created_at).localeCompare(String(right.created_at)) ||
    String(left.submission_id).localeCompare(String(right.submission_id))
  )
}

function publicEntries(records, limit) {
  return records.slice(0, limit).map((record, index) => ({
    rank: index + 1,
    name: record.name,
    score: record.score,
    stage_id: record.stage_id,
    victory: record.victory,
    stars: record.stars,
    created_at: record.created_at,
  }))
}

export class LeaderboardStore {
  constructor(dataFile, { now = () => new Date() } = {}) {
    this.dataFile = resolve(dataFile)
    this.now = now
    this.records = []
    this.writeQueue = Promise.resolve()
    this.load()
  }

  load() {
    if (!existsSync(this.dataFile)) return
    let parsed
    try {
      parsed = JSON.parse(readFileSync(this.dataFile, 'utf8'))
    } catch (error) {
      throw new Error(`could not read leaderboard data at ${this.dataFile}: ${error.message}`)
    }
    const stored = Array.isArray(parsed) ? parsed : parsed?.records
    if (!Array.isArray(stored)) return
    const records = []
    for (const raw of stored) {
      try {
        const submission = validateSubmission(raw)
        if (typeof raw.created_at !== 'string') continue
        records.push({
          ...submission,
          score: calculateScore(submission),
          created_at: raw.created_at,
        })
      } catch {
        // Ignore malformed individual rows while preserving valid history.
      }
    }
    this.records = records.sort(compareRecords).slice(0, MAX_RECORDS)
  }

  list(limit = DEFAULT_LIMIT) {
    return publicEntries(this.records, Math.min(MAX_LIMIT, Math.max(1, limit)))
  }

  submit(rawSubmission) {
    const submission = validateSubmission(rawSubmission)
    const operation = async () => {
      let record = this.records.find(
        (candidate) => candidate.submission_id === submission.submission_id,
      )
      let duplicate = true
      if (!record) {
        duplicate = false
        record = {
          ...submission,
          score: calculateScore(submission),
          created_at: this.now().toISOString(),
        }
        this.records.push(record)
        this.records.sort(compareRecords)
        this.records = this.records.slice(0, MAX_RECORDS)
        await this.persist()
      }
      const rank =
        this.records.findIndex(
          (candidate) => candidate.submission_id === record.submission_id,
        ) + 1
      return {
        duplicate,
        entry: {
          rank: rank || null,
          name: record.name,
          score: record.score,
          stage_id: record.stage_id,
          victory: record.victory,
          stars: record.stars,
          created_at: record.created_at,
        },
        entries: this.list(DEFAULT_LIMIT),
      }
    }
    this.writeQueue = this.writeQueue.then(operation, operation)
    return this.writeQueue
  }

  async persist() {
    mkdirSync(dirname(this.dataFile), { recursive: true })
    const temporary = `${this.dataFile}.${process.pid}.${Date.now()}.tmp`
    await writeFile(
      temporary,
      `${JSON.stringify({ version: 1, records: this.records }, null, 2)}\n`,
      { encoding: 'utf8', mode: 0o600 },
    )
    await rename(temporary, this.dataFile)
  }
}

class RequestError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
  }
}

function sendJson(response, status, payload) {
  response.writeHead(status, JSON_HEADERS)
  response.end(JSON.stringify(payload))
}

function requestBody(request, maximumBytes = 16 * 1024) {
  return new Promise((resolveBody, rejectBody) => {
    let size = 0
    let rejected = false
    const chunks = []
    request.on('data', (chunk) => {
      size += chunk.length
      if (size > maximumBytes) {
        if (!rejected) {
          rejected = true
          rejectBody(new RequestError(413, 'request body is too large'))
        }
        return
      }
      chunks.push(chunk)
    })
    request.on('end', () => {
      if (rejected) return
      try {
        resolveBody(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'))
      } catch {
        rejectBody(new RequestError(400, 'request body must be valid JSON'))
      }
    })
    request.on('error', rejectBody)
  })
}

function createRateLimiter({ maximum = 20, windowMs = 60_000 } = {}) {
  const clients = new Map()
  return (address) => {
    const now = Date.now()
    const current = clients.get(address)
    if (!current || current.resetAt <= now) {
      clients.set(address, { count: 1, resetAt: now + windowMs })
      return true
    }
    current.count += 1
    return current.count <= maximum
  }
}

function applySecurityHeaders(response) {
  response.setHeader('X-Content-Type-Options', 'nosniff')
  response.setHeader('Referrer-Policy', 'no-referrer')
  response.setHeader('Cross-Origin-Opener-Policy', 'same-origin')
  response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp')
  response.setHeader('Cross-Origin-Resource-Policy', 'same-origin')
}

function applyCors(request, response, allowedOrigin) {
  if (!allowedOrigin) return
  const requestOrigin = request.headers.origin
  if (allowedOrigin === '*' || requestOrigin === allowedOrigin) {
    response.setHeader(
      'Access-Control-Allow-Origin',
      allowedOrigin === '*' ? '*' : requestOrigin,
    )
    response.setHeader('Access-Control-Allow-Headers', 'Content-Type')
    response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    response.setHeader('Vary', 'Origin')
  }
}

function serveStatic(response, webRoot, pathname, method) {
  let decodedPath
  try {
    decodedPath = decodeURIComponent(pathname)
  } catch {
    sendJson(response, 400, { error: 'invalid URL encoding' })
    return
  }
  const relativePath =
    decodedPath === '/' ? 'index.html' : decodedPath.replace(/^\/+/, '')
  const absolutePath = resolve(webRoot, relativePath)
  const rootPrefix = webRoot.endsWith(sep) ? webRoot : `${webRoot}${sep}`
  if (absolutePath !== webRoot && !absolutePath.startsWith(rootPrefix)) {
    sendJson(response, 403, { error: 'forbidden' })
    return
  }
  if (!existsSync(absolutePath)) {
    sendJson(response, 404, { error: 'not found' })
    return
  }
  response.writeHead(200, {
    'Content-Type':
      MIME_TYPES[extname(absolutePath).toLowerCase()] ||
      'application/octet-stream',
    'Cache-Control':
      extname(absolutePath) === '.html'
        ? 'no-cache'
        : 'public, max-age=3600',
  })
  if (method === 'HEAD') response.end()
  else createReadStream(absolutePath).pipe(response)
}

export function createLeaderboardServer({
  dataFile = resolve('server-data/leaderboard.json'),
  webRoot = resolve('build/web'),
  allowedOrigin = process.env.LEADERBOARD_ALLOW_ORIGIN || '',
  rateLimit = {},
  now,
} = {}) {
  const resolvedWebRoot = resolve(webRoot)
  const store = new LeaderboardStore(dataFile, { now })
  const allowSubmission = createRateLimiter(rateLimit)
  const server = createServer(async (request, response) => {
    applySecurityHeaders(response)
    applyCors(request, response, allowedOrigin)
    try {
      const url = new URL(
        request.url || '/',
        `http://${request.headers.host || 'localhost'}`,
      )
      if (request.method === 'OPTIONS') {
        response.writeHead(204)
        response.end()
        return
      }
      if (url.pathname === '/api/health' && request.method === 'GET') {
        sendJson(response, 200, { ok: true, score_version: SCORE_VERSION })
        return
      }
      if (url.pathname === '/api/leaderboard' && request.method === 'GET') {
        const requestedLimit = Number.parseInt(
          url.searchParams.get('limit') || `${DEFAULT_LIMIT}`,
          10,
        )
        const limit = Number.isFinite(requestedLimit)
          ? requestedLimit
          : DEFAULT_LIMIT
        sendJson(response, 200, {
          score_version: SCORE_VERSION,
          entries: store.list(limit),
        })
        return
      }
      if (url.pathname === '/api/leaderboard' && request.method === 'POST') {
        const address = request.socket.remoteAddress || 'unknown'
        if (!allowSubmission(address)) {
          throw new RequestError(429, 'too many submissions; try again shortly')
        }
        const body = await requestBody(request)
        const result = await store.submit(body)
        sendJson(response, result.duplicate ? 200 : 201, {
          score_version: SCORE_VERSION,
          ...result,
        })
        return
      }
      if (url.pathname.startsWith('/api/')) {
        sendJson(response, 404, { error: 'API route not found' })
        return
      }
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        sendJson(response, 405, { error: 'method not allowed' })
        return
      }
      serveStatic(response, resolvedWebRoot, url.pathname, request.method)
    } catch (error) {
      if (!response.headersSent) {
        const status = error instanceof RequestError ? error.status : 500
        sendJson(response, status, {
          error: status === 500 ? 'internal server error' : error.message,
        })
      }
      if (!(error instanceof RequestError)) {
        console.error('[LEADERBOARD_ERROR]', error)
      }
    }
  })
  return { server, store }
}

function argumentValue(name, fallback) {
  const index = process.argv.indexOf(name)
  return index >= 0 && process.argv[index + 1]
    ? process.argv[index + 1]
    : fallback
}

const invokedPath = process.argv[1]
  ? pathToFileURL(resolve(process.argv[1])).href
  : ''
if (invokedPath === import.meta.url) {
  const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
  const host = argumentValue('--host', process.env.HOST || '127.0.0.1')
  const port = Number.parseInt(
    argumentValue('--port', process.env.PORT || '3000'),
    10,
  )
  const webRootArgument = argumentValue(
    '--web-root',
    process.env.WEB_ROOT || resolve(projectRoot, 'build/web'),
  )
  const dataFileArgument = argumentValue(
    '--data-file',
    process.env.LEADERBOARD_DATA_FILE ||
      resolve(projectRoot, 'server-data/leaderboard.json'),
  )
  const { server } = createLeaderboardServer({
    webRoot: isAbsolute(webRootArgument)
      ? webRootArgument
      : resolve(projectRoot, webRootArgument),
    dataFile: isAbsolute(dataFileArgument)
      ? dataFileArgument
      : resolve(projectRoot, dataFileArgument),
  })
  server.listen(port, host, () => {
    console.log(
      `[LEADERBOARD] game and API listening at http://${host}:${port}`,
    )
  })
}
