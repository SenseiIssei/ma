import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { ADMIN, startServer } from './helpers.mjs';

function deck(overrides = {}) {
  const cards = Array.from({ length: 6 }, (_, i) => ({
    id: `birds-${String(i + 1).padStart(3, '0')}`,
    prompt: `Bird number ${i + 1}?`,
    answer: `Answer ${i + 1}`,
    distractors: ['One', 'Two', 'Three'],
    example: `The right one is Answer ${i + 1} here.`,
    note: 'A note.',
  }));
  return { id: 'birds', title: 'Garden birds', subtitle: 'Who sings outside', symbol: 'B', category: 'knowledge', cards, ...overrides };
}

describe('gallery submissions', () => {
  let s;
  before(async () => {
    s = await startServer();
  });
  after(() => s.close());

  it('stores a valid deck for review without auth', async () => {
    const res = await s.request('POST', '/gallery/submissions', { body: deck() });
    assert.equal(res.status, 201);
    assert.equal(res.body.status, 'pending');
  });

  it('rejects decks that do not match the schema', async () => {
    const d = deck();
    const bad = [
      deck({ title: '' }),
      deck({ cards: [] }),
      deck({ category: 'memes' }),
      deck({ author: 'me@example.com' }),
      deck({ cards: d.cards.map((c, i) => (i === 0 ? { ...c, answer: '' } : c)) }),
      deck({ cards: d.cards.map((c, i) => (i === 0 ? { ...c, distractors: ['a', 'b'] } : c)) }),
      deck({ cards: d.cards.map((c, i) => (i === 0 ? { ...c, example: 'No answer in here' } : c)) }),
      deck({ cards: d.cards.map((c, i) => (i === 0 ? { ...c, secret: 'x' } : c)) }),
      deck({ cards: d.cards.map((c) => ({ ...c, id: 'same' })) }),
      [1, 2, 3],
    ];
    for (const body of bad) {
      const res = await s.request('POST', '/gallery/submissions', { body });
      assert.equal(res.status, 400, JSON.stringify(body).slice(0, 120));
    }
  });

  it('refuses bodies over 200 KB', async () => {
    const huge = deck({ cards: deck().cards.map((c) => ({ ...c, note: 'x'.repeat(40_000) })) });
    const res = await s.request('POST', '/gallery/submissions', { body: huge });
    assert.equal(res.status, 413);
  });

  it('lists submissions only for the admin', async () => {
    const none = await s.request('GET', '/gallery/submissions');
    assert.equal(none.status, 401);
    const wrong = await s.request('GET', '/gallery/submissions', { token: 'nope' });
    assert.equal(wrong.status, 401);
    const m = await s.newMember();
    const member = await s.request('GET', '/gallery/submissions', { token: m.token });
    assert.equal(member.status, 401);

    const ok = await s.request('GET', '/gallery/submissions', { token: ADMIN });
    assert.equal(ok.status, 200);
    assert.ok(ok.body.submissions.length >= 1);
    const sub = ok.body.submissions[0];
    assert.equal(sub.title, 'Garden birds');
    assert.equal(sub.deck.cards.length, 6);

    const marked = await s.request('PATCH', `/gallery/submissions/${sub.id}`, { token: ADMIN, body: { status: 'accepted' } });
    assert.equal(marked.status, 200);
    const pending = await s.request('GET', '/gallery/submissions', { token: ADMIN });
    assert.equal(pending.body.submissions.find((x) => x.id === sub.id), undefined);
    const del = await s.request('DELETE', `/gallery/submissions/${sub.id}`, { token: ADMIN });
    assert.equal(del.status, 204);
  });

  it('switches the admin endpoints off without ADMIN_TOKEN', async () => {
    const off = await startServer({ ADMIN_TOKEN: '' });
    try {
      const res = await off.request('GET', '/gallery/submissions', { token: '' });
      assert.equal(res.status, 404);
    } finally {
      await off.close();
    }
  });
});
