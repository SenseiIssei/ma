import { randomBytes } from 'node:crypto';
import net from 'node:net';
import tls from 'node:tls';

// A small SMTP client for the few mails this service sends: confirm an
// address, reset a password. STARTTLS on 587 or TLS from the start on 465,
// AUTH PLAIN, one message per connection. No dependency, like the rest.

const TIMEOUT_MS = 20_000;

export function mailConfigured(mail) {
  return Boolean(mail.host && mail.from);
}

function encodeHeader(text) {
  // Non-ASCII subjects go out as RFC 2047 base64 words.
  return /^[\x20-\x7e]*$/.test(text) ? text : `=?UTF-8?B?${Buffer.from(text, 'utf8').toString('base64')}?=`;
}

function addressOnly(from) {
  const match = /<([^>]+)>/.exec(from);
  return (match ? match[1] : from).trim();
}

/** Builds the raw message; plain text plus HTML, both UTF-8. */
export function buildMessage({ from, to, subject, text, html, now = new Date() }) {
  const boundary = `ma-${randomBytes(12).toString('hex')}`;
  const domain = addressOnly(from).split('@')[1] || 'localhost';
  const lines = [
    `From: ${from}`,
    `To: ${to}`,
    `Subject: ${encodeHeader(subject)}`,
    `Date: ${now.toUTCString()}`,
    `Message-ID: <${randomBytes(16).toString('hex')}@${domain}>`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    '',
    `--${boundary}`,
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    ...Buffer.from(text, 'utf8').toString('base64').match(/.{1,76}/g),
    `--${boundary}`,
    'Content-Type: text/html; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    ...Buffer.from(html, 'utf8').toString('base64').match(/.{1,76}/g),
    `--${boundary}--`,
    '',
  ];
  return lines.join('\r\n');
}

/** Reads SMTP replies line by line; multi-line replies end on "NNN ". */
function replyReader(socket) {
  let buffer = '';
  let waiting = null;
  const queue = [];
  function pump() {
    while (true) {
      const lines = buffer.split('\r\n');
      let end = -1;
      for (let index = 0; index < lines.length - 1; index++) {
        if (/^\d{3} /.test(lines[index])) {
          end = index;
          break;
        }
      }
      if (end < 0) return;
      const reply = lines.slice(0, end + 1);
      buffer = lines.slice(end + 1).join('\r\n');
      const code = Number(reply[end].slice(0, 3));
      const message = { code, text: reply.join('\n') };
      if (waiting) {
        const resolve = waiting;
        waiting = null;
        resolve(message);
      } else {
        queue.push(message);
      }
    }
  }
  const onData = (chunk) => {
    buffer += chunk.toString('utf8');
    pump();
  };
  socket.on('data', onData);
  return {
    next() {
      if (queue.length) return Promise.resolve(queue.shift());
      return new Promise((resolve) => {
        waiting = resolve;
      });
    },
    detach() {
      socket.off('data', onData);
    },
  };
}

export async function sendMail(mail, { to, subject, text, html }) {
  if (!mailConfigured(mail)) throw new Error('mail is not configured');
  let socket = mail.secure
    ? tls.connect({ host: mail.host, port: mail.port, servername: mail.host })
    : net.connect({ host: mail.host, port: mail.port });
  socket.setTimeout(TIMEOUT_MS, () => socket.destroy(new Error('SMTP timeout')));
  const failed = new Promise((_, reject) => socket.once('error', reject));
  let reader = replyReader(socket);

  async function expect(codes) {
    const reply = await Promise.race([reader.next(), failed]);
    if (!codes.includes(reply.code)) throw new Error(`SMTP ${reply.code}: ${reply.text.slice(0, 200)}`);
    return reply;
  }
  async function command(line, codes) {
    socket.write(`${line}\r\n`);
    return expect(codes);
  }

  try {
    await expect([220]);
    const hello = await command('EHLO ma-friends', [250]);
    if (!mail.secure && /STARTTLS/i.test(hello.text)) {
      await command('STARTTLS', [220]);
      reader.detach();
      socket = tls.connect({ socket, servername: mail.host });
      await new Promise((resolve, reject) => {
        socket.once('secureConnect', resolve);
        socket.once('error', reject);
      });
      reader = replyReader(socket);
      await command('EHLO ma-friends', [250]);
    } else if (!mail.secure && !['127.0.0.1', 'localhost', '::1'].includes(mail.host)) {
      // Plain text only to a relay on this machine (and the test server).
      throw new Error('SMTP server offers no STARTTLS; refusing to send credentials in clear text');
    }
    if (mail.user) {
      const token = Buffer.from(`\u0000${mail.user}\u0000${mail.pass}`, 'utf8').toString('base64');
      await command(`AUTH PLAIN ${token}`, [235]);
    }
    await command(`MAIL FROM:<${addressOnly(mail.from)}>`, [250]);
    await command(`RCPT TO:<${to}>`, [250, 251]);
    await command('DATA', [354]);
    const body = buildMessage({ from: mail.from, to, subject, text, html })
      // Dot-stuffing: a line starting with "." gets a second one.
      .replace(/\r\n\./g, '\r\n..');
    socket.write(`${body}\r\n.\r\n`);
    await expect([250]);
    await command('QUIT', [221]).catch(() => {});
  } finally {
    socket.destroy();
  }
}
