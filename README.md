# haxe-sockets
A streamlined, cross-platform socket library for Haxe that mimics the AIR SDK / OpenFL API while using native Haxe types.

## Features

`hxSockets.Socket` (plain TCP) and `hxSockets.SecureSocket` (TLS/SSL) provide an
event-driven API (`onConnect`, `onClose`, `onData`, `onError`) over native Haxe
sockets. The library also offers:

- **Mutual TLS (client certificates).** `SecureSocket.setClientCertificate(certPemPath, keyPemPath, ?caPemPath)`
  presents a client certificate during the handshake. `setCA(caPemPath)` pins a
  server CA. Both are no-ops when not set.
- **Manual-poll mode.** Construct with `new Socket(true)` / `new SecureSocket(true)`
  (or call `setManualPoll(true)`) to disable the internal `haxe.Timer` and drive
  I/O yourself by calling `poll()`. The default is Timer-driven.
- **Non-reallocating receive buffer.** Incoming data is held in a reusable
  buffer (`hxSockets.ReceiveBuffer`).
- **Partial-read helpers.** `readExactly(n)` (returns null until n bytes are
  buffered), `hasAvailable(n)`, and a non-destructive `peekBytes(n)`. Build your
  own framing on top of these.
- **Reconnect-safe lifecycle.** `close()` is idempotent and resets state, so an
  instance can be re-`connect()`ed.
- **Typed errors.** Set `onErrorKind(SocketErrorKind, String)` to distinguish
  `ConnectionLost`, `Timeout`, `TlsHandshakeFailed`, `CertificateRejected` and
  `Other`.

## Tests

The test suite uses `utest`. Build and run on the C++ target:

```
haxe tests_cpp.hxml
```

Type-check only (no compiler required):

```
haxe tests_check.hxml
```

The mTLS tests need an `openssl` binary on `PATH` to generate throwaway
certificates; they SKIP when openssl is absent. Some `SecureSocketTests` connect
to `example.com:443` and require internet access.
