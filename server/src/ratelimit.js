// Token buckets kept in memory. A restart forgets them, which is fine: the
// point is to blunt floods and code guessing, not to meter usage exactly.

export class RateLimiter {
  /**
   * @param {number} capacity  burst size
   * @param {number} perMs     tokens added per millisecond
   * @param {() => number} now clock, injectable for tests
   */
  constructor(capacity, perMs, now = Date.now) {
    this.capacity = capacity;
    this.perMs = perMs;
    this.now = now;
    this.buckets = new Map();
  }

  static perMinute(capacity, perMinute, now) {
    return new RateLimiter(capacity, perMinute / 60_000, now);
  }

  static perHour(capacity, perHour, now) {
    return new RateLimiter(capacity, perHour / 3_600_000, now);
  }

  /** Takes one token. Returns 0 when allowed, else the seconds to wait. */
  take(key) {
    const t = this.now();
    let b = this.buckets.get(key);
    if (!b) {
      // Bound memory under a flood of distinct keys: drop the oldest.
      if (this.buckets.size >= 50_000) this.sweep(true);
      b = { tokens: this.capacity, at: t };
      this.buckets.set(key, b);
    } else {
      // max(0, ...) so a clock that steps backwards cannot drain a bucket.
      b.tokens = Math.min(this.capacity, b.tokens + Math.max(0, t - b.at) * this.perMs);
      b.at = t;
    }
    if (b.tokens >= 1) {
      b.tokens -= 1;
      return 0;
    }
    if (this.perMs <= 0) return 3600;
    return Math.max(1, Math.ceil((1 - b.tokens) / this.perMs / 1000));
  }

  /** Forgets buckets that have refilled completely; they carry no state. */
  sweep(force = false) {
    const t = this.now();
    for (const [key, b] of this.buckets) {
      const tokens = b.tokens + (t - b.at) * this.perMs;
      if (tokens >= this.capacity) this.buckets.delete(key);
    }
    if (force && this.buckets.size >= 50_000) {
      const drop = this.buckets.size - 40_000;
      let i = 0;
      for (const key of this.buckets.keys()) {
        if (i++ >= drop) break;
        this.buckets.delete(key);
      }
    }
  }
}
