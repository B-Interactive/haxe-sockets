'use strict';

// Loopback TCP peer for hxSockets interop tests. Plain bytes only, Node stdlib
// only (no dependencies). Behaviour is selected with --mode. Once listening,
// exactly one handshake line is written to stdout: "READY <host> <port>\n".
// All diagnostics go to stderr so the stdout parser stays trivial.

const net = require('net');

const HOST = '127.0.0.1';
const MODES = ['echo', 'chunks', 'close-after-bytes', 'close-after-accept'];

function fail(message, code) {
  process.stderr.write(`peer: ${message}\n`);
  process.exit(code || 1);
}

function intOption(name, raw) {
  const n = Number.parseInt(raw, 10);
  if (!Number.isInteger(n) || n < 0) {
    fail(`invalid ${name}: ${raw}`, 2);
  }
  return n;
}

// --payload accepts UTF-8 text, or hex when prefixed with "hex:".
function decodePayload(value) {
  if (value.startsWith('hex:')) {
    const hex = value.slice(4);
    if (hex.length % 2 !== 0 || !/^([0-9a-fA-F]{2})*$/.test(hex)) {
      fail(`invalid hex payload: ${value}`, 2);
    }
    return Buffer.from(hex, 'hex');
  }
  return Buffer.from(value, 'utf8');
}

function parseArgs(argv) {
  const opts = { mode: null, chunkCount: 3, chunkSize: 64, delayMs: 20, payload: null };
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    const raw = argv[i + 1];
    if (raw === undefined) {
      fail(`missing value for ${key}`, 2);
    }
    switch (key) {
      case '--mode':
        opts.mode = raw;
        break;
      case '--chunk-count':
        opts.chunkCount = intOption('--chunk-count', raw);
        break;
      case '--chunk-size':
        opts.chunkSize = intOption('--chunk-size', raw);
        break;
      case '--delay-ms':
        opts.delayMs = intOption('--delay-ms', raw);
        break;
      case '--payload':
        opts.payload = decodePayload(raw);
        break;
      default:
        fail(`unknown option: ${key}`, 2);
    }
    i++;
  }
  return opts;
}

function serve(server, opts) {
  server.on('connection', (sock) => {
    // The client may close early; EOF on our side is expected, not a fault.
    sock.on('error', () => {});

    switch (opts.mode) {
      case 'echo':
        // Write client data straight back (Node may coalesce chunks).
        sock.on('data', (data) => sock.write(data));
        break;

      case 'chunks': {
        // Ignore input; stream fixed chunks with small delays. Without
        // --payload, chunk i is chunkSize copies of the byte value i.
        let i = 0;
        const sendNext = () => {
          if (i >= opts.chunkCount) {
            return;
          }
          const chunk = opts.payload || Buffer.alloc(opts.chunkSize, i % 256);
          sock.write(chunk);
          i++;
          if (i < opts.chunkCount) {
            setTimeout(sendNext, opts.delayMs);
          }
        };
        sendNext();
        break;
      }

      case 'close-after-bytes':
        // Send a known payload, then FIN after a short drain grace.
        sock.write(opts.payload || Buffer.from('GOODBYE', 'utf8'));
        setTimeout(() => {
          sock.end();
          server.close(() => process.exit(0));
        }, 50);
        break;

      case 'close-after-accept':
        // Accept then FIN quickly: a clean peer EOF with no payload.
        sock.end();
        server.close(() => process.exit(0));
        break;
    }
  });
}

const opts = parseArgs(process.argv.slice(2));
if (!opts.mode || !MODES.includes(opts.mode)) {
  fail(
    `usage: node peer.js --mode <${MODES.join('|')}> ` +
      '[--chunk-count N] [--chunk-size N] [--delay-ms N] [--payload text|hex:ABCD]',
    2
  );
}

const server = net.createServer();
server.on('error', (err) => fail(`listen failed: ${err.message}`));
serve(server, opts);

server.listen(0, HOST, () => {
  const { port } = server.address();
  process.stdout.write(`READY ${HOST} ${port}\n`);
});
