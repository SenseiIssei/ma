import { createApp } from './app.js';
import { loadConfig } from './config.js';

// Entry point: listen, and shut down cleanly on SIGTERM so `docker stop`
// never cuts a SQLite write in half.

const config = loadConfig();
const app = createApp({ config });

app.server.listen(config.port, config.host, () => {
  console.log(`[friends] listening on ${config.host}:${config.port}${config.basePath || '/'} data=${config.dataDir}`);
});

let stopping = false;
async function shutdown(signal) {
  if (stopping) return;
  stopping = true;
  console.log(`[friends] ${signal}, shutting down`);
  // In-flight requests get a few seconds, then open sockets are cut.
  const force = setTimeout(() => {
    app.server.closeAllConnections?.();
  }, 8_000);
  force.unref();
  try {
    await app.close();
    console.log('[friends] bye');
    process.exit(0);
  } catch (err) {
    console.error('[friends] shutdown failed:', err);
    process.exit(1);
  }
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
