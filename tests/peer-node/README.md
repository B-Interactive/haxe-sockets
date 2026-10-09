# hxSockets Node peer

A tiny loopback TCP peer used by the hxSockets interop tests (`NodePeerTests`).
It speaks plain bytes only — no framing codec, no dependencies — and is built
purely on the Node standard library (`net`). The verified runtime is
**Node.js 26.x**, though the script itself needs nothing special.

## Modes

| Mode | Behaviour |
|------|-----------|
| `echo` | Writes back whatever the client sends (chunks may coalesce). |
| `chunks` | Ignores input; writes `--chunk-count` chunks of `--chunk-size` bytes with `--delay-ms` between them. Without `--payload`, chunk *i* is `chunkSize` copies of the byte value *i*. |
| `close-after-bytes` | Sends `--payload` (or `GOODBYE`), then closes. |
| `close-after-accept` | Accepts then closes immediately (clean EOF, no payload). |

## Contract

The peer binds `127.0.0.1` on an ephemeral port. Once listening it writes
exactly one line to stdout:

```text
READY 127.0.0.1 <port>
```

All diagnostics go to stderr, and the process exits non-zero if binding fails.
The Haxe driver (`tests/hxSockets/tests/NodePeer.hx`) parses only that READY
line.

## Manual debugging

Run a peer by hand from the repository root, then connect any TCP client to the
reported port:

```bash
node tests/peer-node/peer.js --mode echo
# READY 127.0.0.1 41234  -> then: nc 127.0.0.1 41234

node tests/peer-node/peer.js --mode chunks --chunk-count 3 --chunk-size 16 --delay-ms 50
node tests/peer-node/peer.js --mode close-after-bytes --payload "hex:0A0B0C"
node tests/peer-node/peer.js --mode close-after-accept
```

TLS/mTLS modes are not implemented yet; this harness covers plain TCP only.
