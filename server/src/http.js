// Small request and response helpers so the route files read like a spec.

export class HttpError extends Error {
  constructor(status, code, message, headers = {}) {
    super(message || code);
    this.status = status;
    this.code = code;
    this.headers = headers;
  }
}

export const badRequest = (message) => new HttpError(400, 'bad_request', message);
export const notFound = (message = 'Not found') => new HttpError(404, 'not_found', message);
export const forbidden = (message = 'Forbidden') => new HttpError(403, 'forbidden', message);
export const conflict = (message) => new HttpError(409, 'conflict', message);

const BASE_HEADERS = {
  // Nothing here is cacheable: every answer is private to one member.
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
};

export function send(res, status, body, headers = {}) {
  if (res.headersSent) return;
  if (body === undefined || status === 204) {
    res.writeHead(status, { ...BASE_HEADERS, ...headers });
    res.end();
    return;
  }
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    ...BASE_HEADERS,
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    ...headers,
  });
  res.end(payload);
}

export function sendError(res, err) {
  if (err instanceof HttpError) {
    send(res, err.status, { error: err.code, message: err.message }, err.headers);
    return;
  }
  send(res, 500, { error: 'internal', message: 'Something went wrong' });
}

/**
 * Reads the body as JSON, refusing anything over `limit` bytes. The limit is
 * checked on Content-Length first and again while streaming, because a
 * client can lie about the length or send chunked data without one.
 */
export function readJson(req, limit) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] ?? NaN);
    if (Number.isFinite(declared) && declared > limit) {
      reject(new HttpError(413, 'too_large', `Body larger than ${limit} bytes`));
      req.resume();
      return;
    }
    const chunks = [];
    let size = 0;
    let failed = false;
    req.on('data', (chunk) => {
      if (failed) return;
      size += chunk.length;
      if (size > limit) {
        failed = true;
        reject(new HttpError(413, 'too_large', `Body larger than ${limit} bytes`));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (failed) return;
      if (size === 0) {
        resolve(undefined);
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(badRequest('Body is not valid JSON'));
      }
    });
    req.on('error', (err) => {
      if (!failed) reject(err);
    });
  });
}

export function clientIp(req, trustProxy) {
  if (trustProxy) {
    const real = req.headers['x-real-ip'];
    if (typeof real === 'string' && real.length > 0 && real.length <= 64) return real.trim();
  }
  return req.socket.remoteAddress || 'unknown';
}

/** Seconds-precision ISO time; Swift's .iso8601 decoder rejects milliseconds. */
export function isoTime(ms) {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
}
