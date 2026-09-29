import { strict as assert } from 'node:assert';
import { randomBytes } from 'node:crypto';
import { describe, it } from 'node:test';
import { RateLimiter } from '../src/ratelimit.js';
import { startServer } from './helpers.mjs';

describe('token bucket', () => {
  it('allows a burst, then refills over time', () => {
    const clock = { t: 0 };
    const l = RateLimiter.perMinute(3, 60, () => clock.t);
    assert.equal(l.take('a'), 0);
    assert.equal(l.take('a'), 0);
    assert.equal(l.take('a'), 0);
    assert.equal(l.take('a'), 1);
    assert.equal(l.take('b'), 0, 'keys are independent');
    clock.t += 1000;
    assert.equal(l.take('a'), 0);
    assert.ok(l.take('a') > 0);
  });

  it('forgets full buckets on sweep', () => {
    const clock = { t: 0 };
    const l = RateLimiter.perMinute(2, 60, () => clock.t);
    l.take('x');
    clock.t += 10_000;
    l.sweep();
    assert.equal(l.buckets.size, 0);
  });
});

describe('rate limits over HTTP', () => {
  it('limits per IP with 429 and Retry-After', async () => {
    const s = await startServer({ RATE_IP_CAPACITY: '3', RATE_IP_PER_MINUTE: '1' });
    try {
      const m = await s.newMember();
      let last;
      for (let i = 0; i < 5; i++) last = await s.request('GET', '/me', { token: m.token, ip: '203.0.113.7' });
      assert.equal(last.status, 429);
      assert.ok(Number(last.headers.get('retry-after')) >= 1);
      const other = await s.request('GET', '/me', { token: m.token, ip: '203.0.113.8' });
      assert.equal(other.status, 200);
      s.clock.t += 60_000;
      const later = await s.request('GET', '/me', { token: m.token, ip: '203.0.113.7' });
      assert.equal(later.status, 200);
      const health = await s.request('GET', '/health', { ip: '203.0.113.7' });
      assert.equal(health.status, 200, 'health checks are never limited');
    } finally {
      await s.close();
    }
  });

  it('limits per member across addresses', async () => {
    const s = await startServer({ RATE_MEMBER_CAPACITY: '2', RATE_MEMBER_PER_MINUTE: '1' });
    try {
      const m = await s.newMember();
      const codes = [];
      for (let i = 0; i < 4; i++) codes.push((await s.request('GET', '/me', { token: m.token, ip: `198.51.100.${i}` })).status);
      assert.deepEqual(codes, [200, 200, 429, 429]);
    } finally {
      await s.close();
    }
  });

  it('keeps signups and invite code guessing tight', async () => {
    const s = await startServer({ RATE_SIGNUP_CAPACITY: '2', RATE_SIGNUP_PER_HOUR: '1', RATE_JOIN_CAPACITY: '2', RATE_JOIN_PER_HOUR: '1' });
    try {
      const statuses = [];
      for (let i = 0; i < 3; i++) {
        const res = await s.request('POST', '/members', {
          ip: '192.0.2.1',
          body: { secret: randomBytes(32).toString('hex'), nickname: `N${i}` },
        });
        statuses.push(res.status);
      }
      assert.deepEqual(statuses, [201, 201, 429]);

      const m = await s.newMember('Guesser');
      const guesses = [];
      for (let i = 0; i < 3; i++) {
        const res = await s.request('POST', '/circles/join', { token: m.token, ip: `192.0.2.${10 + i}`, body: { code: 'ZZZZZZZZ' } });
        guesses.push(res.status);
      }
      assert.deepEqual(guesses, [404, 404, 429]);
    } finally {
      await s.close();
    }
  });
});
