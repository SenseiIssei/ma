# Ma Friends backend

"Friends without a feed": small circles of up to 20 people who see each other's daily numbers and nothing else. No accounts, no email, no phone numbers, no contacts, no free text besides a nickname and a circle name.

Node 24 with zero npm dependencies (`node:http`, `node:crypto`, `node:sqlite`). One SQLite file in `DATA_DIR`.

## What is stored

| Table | Contents |
| --- | --- |
| `members` | random UUID, SHA-256 of the device secret, nickname (max 24), avatar (one of a fixed list of SF Symbol names), created time |
| `circles` | UUID, name (max 40), creator id, 8 character invite code, chosen challenge kind |
| `circle_members` | who is in which circle, since when |
| `stats` | per member and date: streakDays, focusMinutes, pomodoros, resisted, correctAnswers, habitsDone. Rows older than `STATS_RETENTION_DAYS` (30) are deleted automatically |
| `gallery_submissions` | community decks waiting for manual review, with no submitter identity |

No IP addresses are stored or logged. The rate limiter keeps them in memory only, and a restart forgets them.

## Auth

The app creates a UUID and 32 random bytes on first use and keeps both in the Keychain. It sends the secret once, as 64 lowercase hex characters, in `POST /members`. After that every request carries

```
Authorization: Bearer <memberId>.<secretHex>
```

The server keeps only `sha256(secretHex)` and compares in constant time.

## Endpoints

All paths are below `BASE_PATH` (default `/ma/api`). Bodies are JSON. Unknown fields are rejected with 400, so nothing beyond the listed fields can ever be stored.

| Method and path | Auth | What it does |
| --- | --- | --- |
| `GET /health` | none | `{ "ok": true }`, never rate limited |
| `POST /members` | none | `{ id?, secret, nickname, avatar? }` creates a member, 201 with the profile |
| `GET /me` | member | own profile |
| `PATCH /me` | member | `{ nickname?, avatar? }` |
| `DELETE /me` | member | deletes the member, all numbers and memberships at once; circles they created pass to the longest-standing member or vanish if empty. 204 |
| `POST /circles` | member | `{ name }`, 201 with the circle detail |
| `POST /circles/join` | member | `{ code }` (case and dashes do not matter). Idempotent for existing members |
| `GET /circles` | member | `{ circles: [summary] }` for the circles I am in |
| `GET /circles/:id` | member | detail: members with their last days of numbers, challenge progress. 404 for outsiders |
| `POST /circles/:id/leave` | member | 204. A leaving creator hands over to the next member |
| `POST /circles/:id/rotate-code` | creator | new invite code, the old one stops working |
| `DELETE /circles/:id/members/:memberId` | creator | removes someone, 204 |
| `PUT /circles/:id/challenge` | creator | `{ kind }` from the list below, or `{ kind: null }` to clear |
| `PUT /stats/:date` | member | `{ streakDays, focusMinutes, pomodoros, resisted, correctAnswers, habitsDone }`, all required whole numbers. Only today or yesterday |
| `POST /gallery/submissions` | none | a deck in the app's JSON format, max 200 KB, 5 to 500 cards. 201 `{ id, status: "pending" }` |
| `GET /gallery/submissions?status=pending&limit=50` | admin | review queue with the full deck JSON |
| `PATCH /gallery/submissions/:id` | admin | `{ status: "pending" \| "accepted" \| "rejected" }` |
| `DELETE /gallery/submissions/:id` | admin | removes a submission |

Admin means `Authorization: Bearer <ADMIN_TOKEN>`. Without `ADMIN_TOKEN` the admin endpoints answer 404.

Errors look like `{ "error": "bad_request", "message": "..." }`. Status codes: 400 invalid input, 401 bad credentials, 403 not the creator, 404 not found or not yours, 409 limit reached or id taken, 413 body too large, 429 rate limited (with `Retry-After`), 503 review queue full.

### "Today or yesterday"

The server does not know a member's time zone and should not. It accepts a date when it is today or yesterday somewhere on Earth (UTC-12 to UTC+14).

### Weekly challenges

| kind | rule |
| --- | --- |
| `focus-rounds-each` | 5 pomodoros per member |
| `focus-minutes-together` | 600 focus minutes pooled |
| `resist-together` | 20 resisted impulses pooled |
| `cards-together` | 100 correct answers pooled |
| `cards-each` | 30 correct answers per member |
| `habits-each` | 10 habits done per member |

A week runs Monday to Sunday by UTC date. "each" challenges cap every member at the target, so one busy person cannot carry the circle; they are complete when everyone has reached it. The chosen challenge repeats every week until the creator changes it. Only current members count.

### Limits

20 members per circle, 10 circles per member, invite codes of 8 characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0/O, 1/I/L).

Token buckets in memory: per IP (120 burst, 120 per minute), per member (60, 60 per minute), signups per IP (5, 10 per hour), invite code attempts per member and per IP (10, 30 per hour), gallery submissions per IP (5, 5 per hour). All adjustable through `RATE_*` variables, see `src/config.js`.

## Configuration

| Variable | Default | |
| --- | --- | --- |
| `PORT` | `8095` | |
| `HOST` | `0.0.0.0` | inside the container |
| `BASE_PATH` | `/ma/api` | prefix the service expects; nginx passes it through unchanged |
| `DATA_DIR` | `/data` | holds `friends.sqlite` (plus WAL files) |
| `ADMIN_TOKEN` | empty | enables the gallery review endpoints |
| `TRUST_PROXY` | `1` | take the client address from `X-Real-IP`; set `0` if the port is ever exposed directly |
| `STATS_RETENTION_DAYS` | `30` | older daily numbers are deleted |

## Tests

```
MSYS_NO_PATHCONV=1 docker run --rm -v "F:/Projects/swift/ma/server:/app" -w /app node:24-alpine node --test
```

or `npm test` with Node 24 installed.

## Deploy on the VPS

1. Copy `server/` to `/opt/ma-friends` (or pull the repo and use its `server/` folder).
2. Create `/opt/ma-friends/.env` with `ADMIN_TOKEN=<long random string>` (`openssl rand -hex 32`), `chmod 600`.
3. `cd /opt/ma-friends && docker compose up -d --build`
4. Check: `curl -s http://127.0.0.1:8095/ma/api/health` prints `{"ok":true}` and `docker inspect --format '{{.State.Health.Status}}' ma-friends` says `healthy`.
5. Add this to the `server { ... }` block for senseiissei.dev in the host nginx (`/etc/nginx/sites-available/sensei`), above the catch-all `location /`:

```nginx
location /ma/api/ {
    # No URI after the port: the path reaches the service unchanged,
    # including the /ma/api prefix.
    proxy_pass http://127.0.0.1:8095;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Connection "";
    client_max_body_size 256k;
    proxy_read_timeout 15s;
}
```

6. `nginx -t && systemctl reload nginx`
7. From outside: `curl -s https://senseiissei.dev/ma/api/health`

Backup: the whole state is the `ma-friends-data` volume. Updating: `docker compose up -d --build` again; `stop_grace_period` gives in-flight requests time to finish.
