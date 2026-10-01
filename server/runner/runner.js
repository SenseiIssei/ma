import { spawn } from 'node:child_process';
import { createHash, timingSafeEqual } from 'node:crypto';
import { cp, mkdtemp, readdir, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Compiles and runs C++ for the daily lessons on senseiissei.dev. It lives in
// its own container on an internal network without internet, read-only
// except /tmp, with memory, CPU and process limits set by Docker. Only the Ma
// server can reach it, and only with RUNNER_TOKEN; the Ma server in turn only
// forwards requests from the owner's linked browser.
//
// One request = one compile, then one run per test, each in a fresh folder
// with time, CPU and file size limits. Grading happens in the browser; this
// service only reports what the program did.

const PORT = Number(process.env.PORT || 8096);
const TOKEN = process.env.RUNNER_TOKEN || '';
const COMPILE_TIMEOUT_MS = 30_000;
const MAX_RUN_TIMEOUT_MS = 10_000;
const OUTPUT_CAP = 64 * 1024;
const BODY_LIMIT = 512 * 1024;
const MAX_TESTS = 12;
const MAX_QUEUE = 3;

const FILE_NAME = /^[A-Za-z0-9_-]{1,40}\.(cpp|cc|h|hpp)$/;
const STANDARDS = new Set(['c++17', 'c++20', 'c++23']);
const OPTIMIZE = new Set(['-O0', '-O1', '-O2']);
const SANITIZERS = new Set(['address', 'undefined', 'thread']);

class BadRequest extends Error {}

function sameToken(given) {
  const a = createHash('sha256').update(given).digest();
  const b = createHash('sha256').update(TOKEN).digest();
  return TOKEN.length > 0 && timingSafeEqual(a, b);
}

/** Checks and normalises a run request; throws BadRequest. */
export function parseRequest(body) {
  if (typeof body !== 'object' || body === null) throw new BadRequest('body must be an object');
  const files = body.files;
  if (typeof files !== 'object' || files === null) throw new BadRequest('files are missing');
  const names = Object.keys(files);
  if (names.length === 0 || names.length > 6) throw new BadRequest('one to six files');
  let total = 0;
  for (const name of names) {
    if (!FILE_NAME.test(name)) throw new BadRequest(`bad file name ${name}`);
    if (typeof files[name] !== 'string') throw new BadRequest(`${name} must be text`);
    total += files[name].length;
  }
  if (total > 200_000) throw new BadRequest('the code is too long');
  if (!names.some((name) => /\.(cpp|cc)$/.test(name))) throw new BadRequest('no .cpp file');
  const std = body.std ?? 'c++20';
  if (!STANDARDS.has(std)) throw new BadRequest('std must be c++17, c++20 or c++23');
  const optimize = body.optimize ?? '-O1';
  if (!OPTIMIZE.has(optimize)) throw new BadRequest('optimize must be -O0, -O1 or -O2');
  const sanitizers = Array.isArray(body.sanitizers) ? [...new Set(body.sanitizers)] : [];
  if (!sanitizers.every((name) => SANITIZERS.has(name))) throw new BadRequest('unknown sanitizer');
  if (sanitizers.includes('thread') && sanitizers.includes('address')) throw new BadRequest('thread and address cannot be combined');
  const tests = Array.isArray(body.tests) ? body.tests : [];
  if (tests.length > MAX_TESTS) throw new BadRequest(`at most ${MAX_TESTS} tests`);
  for (const test of tests) {
    if (typeof test.stdin !== 'string' || test.stdin.length > 64 * 1024) throw new BadRequest('stdin must be text up to 64 KB');
  }
  const timeoutMs = Math.min(MAX_RUN_TIMEOUT_MS, Math.max(500, Number(body.timeoutMs) || 5_000));
  return { files, std, optimize, sanitizers, tests: tests.map((test, index) => ({ id: String(test.id ?? index), stdin: test.stdin })), timeoutMs };
}

/** g++ diagnostics as editor markers. */
export function parseDiagnostics(output) {
  const pattern = /^(?:\.\/)?([\w.-]+):(\d+):(\d+): (fatal error|error|warning|note): (.*)$/gm;
  const markers = [];
  for (const match of output.matchAll(pattern)) {
    markers.push({ file: match[1], line: Number(match[2]), column: Number(match[3]), severity: match[4].replace('fatal ', ''), message: match[5] });
  }
  return markers.slice(0, 200);
}

function collect(stream, limit) {
  const chunks = [];
  let size = 0;
  let truncated = false;
  stream.on('data', (chunk) => {
    if (size >= limit) {
      truncated = true;
      return;
    }
    const room = limit - size;
    chunks.push(chunk.length > room ? chunk.subarray(0, room) : chunk);
    size += Math.min(chunk.length, room);
    if (chunk.length > room) truncated = true;
  });
  return () => ({ text: Buffer.concat(chunks).toString('utf8'), truncated });
}

/** Runs a command in its own process group and kills the whole group on timeout. */
function run(command, args, { cwd, stdin = '', timeoutMs, env }) {
  return new Promise((resolve) => {
    const started = process.hrtime.bigint();
    const child = spawn(command, args, { cwd, env, detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
    const stdout = collect(child.stdout, OUTPUT_CAP);
    const stderr = collect(child.stderr, OUTPUT_CAP);
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        process.kill(-child.pid, 'SIGKILL');
      } catch {
        /* already gone */
      }
    }, timeoutMs);
    child.on('error', () => {});
    child.stdin.on('error', () => {});
    child.stdin.end(stdin);
    child.on('close', (exitCode, signal) => {
      clearTimeout(timer);
      // Anything the program forked is cleaned up with it.
      try {
        process.kill(-child.pid, 'SIGKILL');
      } catch {
        /* already gone */
      }
      const out = stdout();
      const err = stderr();
      resolve({
        exitCode,
        signal,
        timedOut,
        timeMs: Number((process.hrtime.bigint() - started) / 1_000_000n),
        stdout: out.text,
        stderr: err.text,
        truncated: out.truncated || err.truncated,
      });
    });
  });
}

/**
 * Jobs run one after another and this service is the container's PID 1, so
 * any other process still alive after a run is a leftover (a fork that
 * escaped its process group, a daemonised child). All of them go.
 */
async function reapStrays() {
  for (let round = 0; round < 3; round++) {
    const pids = (await readdir('/proc').catch(() => [])).filter((name) => /^\d+$/.test(name)).map(Number);
    const strays = pids.filter((pid) => pid !== process.pid && pid !== 1);
    if (strays.length === 0) return;
    for (const pid of strays) {
      try {
        process.kill(pid, 'SIGKILL');
      } catch {
        /* gone already */
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

const BASE_ENV = {
  PATH: '/usr/local/bin:/usr/bin:/bin',
  HOME: '/tmp',
  LANG: 'C.UTF-8',
  ASAN_OPTIONS: 'detect_leaks=1:abort_on_error=0:color=never',
  UBSAN_OPTIONS: 'print_stacktrace=1:halt_on_error=1:color=never',
  TSAN_OPTIONS: 'halt_on_error=1:color=never',
};

export async function compileAndRun(request) {
  const root = await mkdtemp(join(tmpdir(), 'daily-'));
  try {
    for (const [name, text] of Object.entries(request.files)) await writeFile(join(root, name), text);
    const units = Object.keys(request.files).filter((name) => /\.(cpp|cc)$/.test(name));
    const args = [
      `-std=${request.std}`,
      request.optimize,
      '-g',
      '-Wall',
      '-Wextra',
      '-pthread',
      '-fdiagnostics-color=never',
      ...(request.sanitizers.length ? [`-fsanitize=${request.sanitizers.join(',')}`] : []),
      ...units,
      '-o',
      'prog',
    ];
    const compile = await run('g++', args, { cwd: root, timeoutMs: COMPILE_TIMEOUT_MS, env: BASE_ENV });
    const compileOutput = compile.stderr + compile.stdout;
    const compileResult = {
      ok: compile.exitCode === 0 && !compile.timedOut,
      output: compile.timedOut ? 'Compiling took too long.' : compileOutput,
      diagnostics: parseDiagnostics(compileOutput),
      timeMs: compile.timeMs,
    };
    if (!compileResult.ok) return { compile: compileResult, results: [] };

    const results = [];
    for (const test of request.tests) {
      // A fresh folder per test, so files one run writes never leak into the next.
      const folder = await mkdtemp(join(root, 'run-'));
      await cp(join(root, 'prog'), join(folder, 'prog'));
      // CPU seconds, file size (KB) and open files are capped per run; the
      // container caps memory and processes. ThreadSanitizer needs a fixed
      // address layout on newer kernels, hence setarch -R.
      const limits = `ulimit -t ${Math.ceil(request.timeoutMs / 1000) + 1} -f 20480 -n 128 -u 64`;
      const exec = request.sanitizers.includes('thread') ? 'exec setarch "$(uname -m)" -R ./prog' : 'exec ./prog';
      const result = await run('bash', ['-c', `${limits}; ${exec}`], { cwd: folder, stdin: test.stdin, timeoutMs: request.timeoutMs, env: BASE_ENV });
      await reapStrays();
      results.push({ id: test.id, ...result });
    }
    return { compile: compileResult, results };
  } finally {
    await reapStrays();
    await rm(root, { recursive: true, force: true });
  }
}

// One compile at a time keeps the box responsive; a short queue absorbs
// double clicks.
let busy = Promise.resolve();
let waiting = 0;

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > BODY_LIMIT) {
        reject(new BadRequest('body too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'));
      } catch {
        reject(new BadRequest('body is not JSON'));
      }
    });
    req.on('error', reject);
  });
}

function send(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(text) });
  res.end(text);
}

export const server = createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/health') return send(res, 200, { ok: true });
    if (req.method !== 'POST' || req.url !== '/run') return send(res, 404, { error: 'not_found' });
    const header = req.headers.authorization ?? '';
    if (!sameToken(header.startsWith('Bearer ') ? header.slice(7) : '')) return send(res, 401, { error: 'unauthorized' });
    const request = parseRequest(await readBody(req));
    if (waiting >= MAX_QUEUE) return send(res, 429, { error: 'busy', message: 'The compiler is busy, try again in a moment' });
    waiting += 1;
    const job = busy.then(() => compileAndRun(request));
    busy = job.catch(() => {});
    try {
      send(res, 200, await job);
    } finally {
      waiting -= 1;
    }
  } catch (error) {
    if (error instanceof BadRequest) return send(res, 400, { error: 'bad_request', message: error.message });
    console.error('[runner]', error);
    send(res, 500, { error: 'internal' });
  }
});

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split(/[\\/]/).pop())) {
  if (!TOKEN) {
    console.error('[runner] RUNNER_TOKEN is not set, refusing to start');
    process.exit(1);
  }
  server.listen(PORT, '0.0.0.0', () => console.log(`[runner] listening on ${PORT}`));
}
