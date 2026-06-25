package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.SecureSocket;
import hxSockets.SocketErrorKind;
import hxSockets.tests.CertGen;
import hxSockets.tests.MtlsServer;
import haxe.io.Bytes;

/**
 * Mutual-TLS (client certificate) tests for hxSockets.SecureSocket.
 *
 * A local TLS server requires a client certificate signed by a throwaway CA.
 * The positive case connects with setClientCertificate(...) and checks a payload
 * round-trips; the negative case presents no client cert and checks the
 * handshake is rejected. Certificates are generated with openssl into a temp
 * directory and deleted afterwards; the tests SKIP if openssl is unavailable.
 */
class MtlsTests extends Test {
	var certs:CertGen;

	function setup() {
		certs = CertGen.generate();
	}

	function teardown() {
		if (certs != null) {
			certs.cleanup();
			certs = null;
		}
	}

	// Pump poll() until the condition holds or the time budget expires.
	function pump(socket:SecureSocket, condition:Void->Bool, budgetSeconds:Float):Bool {
		var start = Sys.time();
		while (Sys.time() - start < budgetSeconds) {
			socket.poll();
			if (condition()) {
				return true;
			}
			Sys.sleep(0.005);
		}
		return false;
	}

	@:timeout(20000)
	function testClientCertHandshakeSucceeds(async:Async) {
		if (certs == null) {
			Assert.warn("openssl not available - skipping mTLS positive test");
			async.done();
			return;
		}

		var payload = Bytes.ofString("MTLS-OK");
		var server = new MtlsServer(certs.caCert, certs.serverCert, certs.serverKey, payload);
		server.start();

		var socket = new SecureSocket(true); // manual poll
		socket.timeout = 15000;

		var connected = false;
		var failed:String = null;

		socket.onConnect = function() {
			connected = true;
		};
		socket.onError = function(msg) {
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				failed = msg;
			}
		};

		// Present the client cert and pin the server CA. Connect by "localhost"
		// so the cert's DNS SAN matches (resolves to 127.0.0.1 where the server
		// is bound).
		socket.setClientCertificate(certs.clientCert, certs.clientKey, certs.caCert);
		socket.connect("localhost", server.port);

		var ok = pump(socket, function() return connected || failed != null, 15);

		if (failed != null) {
			Assert.fail('mTLS handshake failed: $failed');
			socket.close();
			server.stop();
			async.done();
			return;
		}

		Assert.isTrue(ok, "manual-poll pumping should resolve the handshake");
		Assert.isTrue(connected, "client-cert handshake should succeed");

		// Data round-trips over the authenticated channel.
		var gotData = pump(socket, function() return socket.hasAvailable(payload.length), 5);
		Assert.isTrue(gotData, "should receive the server payload");
		var received = socket.readExactly(payload.length);
		Assert.notNull(received);
		Assert.equals("MTLS-OK", received.toString());

		socket.close();
		server.stop();
		async.done();
	}

	@:timeout(20000)
	function testNoClientCertIsRejected(async:Async) {
		if (certs == null) {
			Assert.warn("openssl not available - skipping mTLS negative test");
			async.done();
			return;
		}

		var payload = Bytes.ofString("SHOULD-NOT-ARRIVE");
		var server = new MtlsServer(certs.caCert, certs.serverCert, certs.serverKey, payload);
		server.start();

		var socket = new SecureSocket(true);
		socket.timeout = 15000;

		var connected = false;
		var rejected = false;
		var rejectKind:SocketErrorKind = null;

		socket.onConnect = function() {
			connected = true;
		};
		socket.onErrorKind = function(kind, msg) {
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				rejected = true;
				rejectKind = kind;
			}
		};

		// Pin the server CA but do not present a client certificate.
		socket.setCA(certs.caCert);
		socket.connect("127.0.0.1", server.port);

		var resolved = pump(socket, function() return connected || rejected, 15);
		Assert.isTrue(resolved, "the attempt should resolve (reject) in time");

		// The server requires a client cert, so the handshake must not succeed.
		Assert.isFalse(connected, "handshake without a client cert must not connect");
		Assert.isTrue(rejected, "missing client cert should be surfaced as an error");
		Assert.isTrue(rejectKind == TlsHandshakeFailed
			|| rejectKind == CertificateRejected
			|| rejectKind == ConnectionLost,
			'rejection kind should be handshake/cert/connection related, got $rejectKind');

		socket.close();
		server.stop();
		async.done();
	}
}
