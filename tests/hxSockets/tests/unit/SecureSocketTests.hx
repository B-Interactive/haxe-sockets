package hxSockets.tests.unit;

import haxe.Exception;
import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.SecureSocket;
import hxSockets.SocketErrorKind;
import hxSockets.X509Certificate;
#if (cpp || neko || hl)
import hxSockets.tests.CertGen;
import hxSockets.tests.MtlsServer;
import hxSockets.tests.SilentServer;
#end
import haxe.io.Bytes;

/**
 * Tests for SecureSocket (TLS/SSL) functionality
 */
class SecureSocketTests extends Test {
	var socket:SecureSocket;

	function setup() {
		socket = new SecureSocket();
	}

	function teardown() {
		if (socket != null && socket.connected) {
			socket.close();
		}
		socket = null;
	}

	// Basic Tests

	function testSecureSocket_NewInstance() {
		Assert.notNull(socket);
		Assert.isFalse(socket.connected);
		Assert.equals(CertificateStatus.UNKNOWN, socket.serverCertificateStatus);
		Assert.isNull(socket.serverCertificate);
	}

	function testSecureSocket_InitialCertificateStatus() {
		Assert.equals(CertificateStatus.UNKNOWN, socket.serverCertificateStatus);
	}

	function testSecureSocket_Close_PreservesFailureStatus() {
		// A terminal failure status survives close() so the cause of a TLS error
		// stays inspectable; any other status resets, as connect() will anyway.
		for (failure in [CertificateStatus.INVALID, CertificateStatus.EXPIRED, CertificateStatus.NOT_YET_VALID]) {
			socket._certificateStatus = failure;
			socket.close();
			Assert.equals(failure, socket.serverCertificateStatus, 'failure status "$failure" should survive close()');
		}

		socket._certificateStatus = CertificateStatus.TRUSTED;
		socket.close();
		Assert.equals(CertificateStatus.UNKNOWN, socket.serverCertificateStatus, "a trusted status should reset on close()");
	}

	// HTTPS Connection Tests

	@:timeout(2000)
	function testSecureSocket_Connect_HTTPS(async:Async) {
		socket.timeout = 15000;
		var connectionComplete = false;

		socket.onConnect = function() {
			if (connectionComplete)
				return; // Prevent double completion
			connectionComplete = true;

			Assert.isTrue(socket.connected);
			Assert.equals(CertificateStatus.TRUSTED, socket.serverCertificateStatus);
			Assert.notNull(socket.serverCertificate);

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			if (connectionComplete)
				return; // Ignore errors after successful connection

			// Only fail on non-blocking errors
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				connectionComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_Certificate_Properties(async:Async) {
		socket.timeout = 15000;
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;

			var cert = socket.serverCertificate;
			Assert.notNull(cert);

			// Subject should exist
			Assert.notNull(cert.subject);
			Assert.notNull(cert.subject.commonName);
			Assert.isTrue(cert.subject.commonName.length > 0);

			// Issuer should exist
			Assert.notNull(cert.issuer);
			Assert.notNull(cert.issuer.commonName);

			// Validity dates
			Assert.notNull(cert.validNotBefore);
			Assert.notNull(cert.validNotAfter);
			Assert.isTrue(cert.validNotAfter.getTime() > cert.validNotBefore.getTime());

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_Certificate_SubjectCN(async:Async) {
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;

			var cert = socket.serverCertificate;
			var cn = cert.subject.commonName;

			// CN should contain or match the domain
			var validCN = (cn.indexOf("example.com") > -1 || cn.indexOf("*.example.com") > -1 || cn == "example.com" || cn.indexOf("example") > -1);

			Assert.isTrue(validCN, 'Common Name "$cn" should relate to example.com');

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_Certificate_ValidityPeriod(async:Async) {
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;

			var cert = socket.serverCertificate;
			var now = Date.now();

			// Certificate should be currently valid
			Assert.isTrue(now.getTime() >= cert.validNotBefore.getTime(), 'Certificate should be valid (notBefore check)');
			Assert.isTrue(now.getTime() <= cert.validNotAfter.getTime(), 'Certificate should not be expired (notAfter check)');

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_SendHTTPS_ReceiveData(async:Async) {
		socket.timeout = 15000;
		var testComplete = false;
		var requestSent = false;

		socket.onConnect = function() {
			if (testComplete || requestSent)
				return;
			requestSent = true;

			var request = "GET / HTTP/1.1\r\n";
			request += "Host: example.com\r\n";
			request += "Connection: close\r\n";
			request += "\r\n";

			socket.writeString(request);
			socket.flush();
		};

		socket.onData = function(bytes) {
			if (testComplete)
				return;
			testComplete = true;

			Assert.isTrue(socket.bytesAvailable > 0);

			var response = socket.readUTFBytes();
			Assert.isTrue(response.length > 0);
			Assert.isTrue(response.indexOf("HTTP/") > -1, 'Response should contain HTTP header');

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Error: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_Properties_AfterConnect(async:Async) {
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;

			Assert.isTrue(socket.connected);
			Assert.notNull(socket.localAddress);
			Assert.isTrue(socket.localPort > 0);
			Assert.notNull(socket.remoteAddress);
			Assert.equals(443, socket.remotePort);

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(15000)
	function testSecureSocket_Timeout(async:Async) {
		socket.timeout = 2000;
		var testComplete = false;

		socket.onError = function(msg) {
			if (testComplete)
				return;

			// Ignore blocking errors
			if (msg.indexOf("Blocked") > -1 || msg.indexOf("Blocking") > -1) {
				return;
			}

			testComplete = true;
			Assert.isTrue(msg.indexOf("timeout") > -1 || msg.indexOf("failed") > -1, 'Error should mention timeout or failure');
			Assert.equals(CertificateStatus.INVALID, socket.serverCertificateStatus);
			async.done();
		};

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;
			Assert.fail("Should not connect to non-routable address");
			async.done();
		};

		// Use non-routable address (TEST-NET-1)
		socket.connect("192.0.2.1", 443);
	}

	#if (cpp || neko || hl)
	@:timeout(15000)
	function testSecureSocket_HandshakeTimeout_WhileWritable(async:Async) {
		// A peer that accepts the TCP connection but never answers the TLS
		// ClientHello leaves the socket writable and the handshake blocked.
		// The wall-clock timeout must still abort the attempt. Manual polling
		// drives the socket deterministically.
		var server = new SilentServer();
		server.start();

		var pollSocket = new SecureSocket(true);
		pollSocket.timeout = 400;

		var connected = false;
		var errorCount = 0;
		var lastKind:SocketErrorKind = null;

		pollSocket.onConnect = function() {
			connected = true;
		};
		pollSocket.onErrorKind = function(kind, msg) {
			errorCount++;
			lastKind = kind;
		};

		var start = Sys.time();
		pollSocket.connect("127.0.0.1", server.port);

		// Pump well past the deadline; the abort must come from the socket.
		while (Sys.time() - start < 3 && errorCount == 0 && !connected) {
			pollSocket.poll();
			Sys.sleep(0.005);
		}
		var elapsed = Sys.time() - start;

		// Keep pumping briefly to check the error fires only once.
		var extraDeadline = Sys.time() + 0.2;
		while (Sys.time() < extraDeadline) {
			pollSocket.poll();
			Sys.sleep(0.005);
		}

		Assert.isTrue(errorCount > 0, "a stalled handshake should abort with a timeout error");
		Assert.equals(Timeout, lastKind, 'error kind should be Timeout, got $lastKind');
		Assert.isFalse(connected, "a stalled handshake must not report connected");
		Assert.isFalse(pollSocket.connected, "the socket should be torn down after the timeout");
		Assert.isTrue(elapsed < 2.0, 'the timeout should abort near the deadline, took ${elapsed}s');
		Assert.equals(1, errorCount, "the timeout should fire once, not repeat after teardown");
		Assert.equals(CertificateStatus.INVALID, pollSocket.serverCertificateStatus,
			"a timeout should leave a failure status that survives teardown");

		pollSocket.close();
		Assert.equals(CertificateStatus.INVALID, pollSocket.serverCertificateStatus,
			"close() after a timeout must not wipe the preserved status");
		server.stop();
		async.done();
	}

	@:timeout(25000)
	function testSecureSocket_WrongCa_KeepsFailureStatusAfterError(async:Async) {
		// A server signed by a throwaway CA is not trusted by the platform roots,
		// so the handshake must fail. The failure status has to stay inspectable
		// after the error callbacks fire and the socket tears down. Manual polling
		// drives the handshake deterministically.
		var certs = CertGen.generate();
		if (certs == null) {
			Assert.warn("openssl not available - skipping wrong-CA status test");
			async.done();
			return;
		}

		var server = new MtlsServer(certs.caCert, certs.serverCert, certs.serverKey, Bytes.ofString("NOPE"));
		server.start();

		var pollSocket = new SecureSocket(true);
		pollSocket.timeout = 8000;

		var connected = false;
		var errored = false;

		pollSocket.onConnect = function() {
			connected = true;
		};
		pollSocket.onError = function(msg) {
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				errored = true;
			}
		};

		// No setCA(): the platform trust store must reject the throwaway CA.
		pollSocket.connect("127.0.0.1", server.port);

		var start = Sys.time();
		while (Sys.time() - start < 12 && !errored && !connected) {
			pollSocket.poll();
			Sys.sleep(0.005);
		}

		Assert.isFalse(connected, "an untrusted server certificate must not connect");
		Assert.isTrue(errored, "the failed handshake should surface through onError");
		Assert.isFalse(pollSocket.connected, "the socket should be torn down after the failure");
		Assert.isTrue(pollSocket.serverCertificateStatus != CertificateStatus.UNKNOWN,
			'a failure status should remain after the error, got ${pollSocket.serverCertificateStatus}');
		Assert.equals(CertificateStatus.INVALID, pollSocket.serverCertificateStatus,
			"an untrusted CA should leave the invalid status");

		pollSocket.close();
		Assert.equals(CertificateStatus.INVALID, pollSocket.serverCertificateStatus,
			"a later close() must not wipe the preserved failure status");

		server.stop();
		certs.cleanup();
		async.done();
	}
	#end

	@:timeout(2000)
	function testSecureSocket_Close_AfterConnect(async:Async) {
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;

			Assert.isTrue(socket.connected);
			Assert.equals(CertificateStatus.TRUSTED, socket.serverCertificateStatus);

			socket.close();
			Assert.isFalse(socket.connected);

			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(3000)
	function testSecureSocket_Reconnect(async:Async) {
		var connectCount = 0;
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			connectCount++;

			if (connectCount == 1) {
				Assert.isTrue(socket.connected);
				Assert.equals(CertificateStatus.TRUSTED, socket.serverCertificateStatus);
				socket.close();

				// Wait a moment then reconnect
				haxe.Timer.delay(function() {
					if (!testComplete) {
						socket.connect("example.com", 443);
					}
				}, 1000);
			} else if (connectCount == 2) {
				testComplete = true;
				Assert.isTrue(socket.connected);
				Assert.equals(CertificateStatus.TRUSTED, socket.serverCertificateStatus);
				socket.close();
				async.done();
			}
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_Certificate_ToString(async:Async) {
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;

			var cert = socket.serverCertificate;
			var certStr = cert.toString();

			Assert.isTrue(certStr.indexOf("X509Certificate") > -1);
			Assert.isTrue(certStr.length > 0);

			var subjectStr = cert.subject.toString();
			Assert.isTrue(subjectStr.indexOf("CN=") > -1);

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_BinaryData_Encrypted(async:Async) {
		var testData = Bytes.alloc(100);
		for (i in 0...100) {
			testData.set(i, i % 256);
		}

		var testComplete = false;
		var dataSent = false;

		socket.onConnect = function() {
			if (testComplete || dataSent)
				return;
			dataSent = true;

			// Write binary data over encrypted connection
			socket.writeBytes(testData);
			socket.flush();

			// Assert that we're connected and data is valid
			Assert.isTrue(socket.connected);
			Assert.equals(CertificateStatus.TRUSTED, socket.serverCertificateStatus);
			Assert.equals(100, testData.length);

			testComplete = true;

			// Give it a moment then close
			haxe.Timer.delay(function() {
				socket.close();
				async.done();
			}, 500);
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	// Error Handling Tests

	function testSecureSocket_WriteBytes_NotConnected() {
		var bytes = Bytes.ofString("test");
		Assert.raises(function() {
			socket.writeBytes(bytes);
		}, Exception);
	}

	function testSecureSocket_ReadBytes_NotConnected() {
		var bytes = Bytes.alloc(10);
		Assert.raises(function() {
			socket.readBytes(bytes);
		}, Exception);
	}

	function testSecureSocket_InvalidPort() {
		var errorCalled = false;
		socket.onError = function(msg) {
			errorCalled = true;
			Assert.isTrue(msg.indexOf("Invalid port") > -1);
		};

		socket.connect("example.com", 65536);
		Assert.isTrue(errorCalled);
	}

	function testSecureSocket_InvalidHost() {
		var errorCalled = false;
		socket.onError = function(msg) {
			errorCalled = true;
			Assert.isTrue(msg.indexOf("Invalid host") > -1);
		};

		socket.connect("", 443);
		Assert.isTrue(errorCalled);
	}

	// Additional robustness tests

	@:timeout(2000)
	function testSecureSocket_ConnectionLifecycle(async:Async) {
		var testComplete = false;
		var connectCalled = false;
		var errorCalled = false;

		socket.onConnect = function() {
			trace("onConnect fired");
			connectCalled = true;
			if (testComplete)
				return;
			testComplete = true;

			Assert.isTrue(socket.connected);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			//trace('onError fired: $msg');
			errorCalled = true;
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);

		// Fallback timeout to provide diagnostic info
		haxe.Timer.delay(function() {
			if (!testComplete) {
				//trace('Test timeout - connectCalled: $connectCalled, errorCalled: $errorCalled');
				if (!connectCalled && !errorCalled) {
					trace("Neither onConnect nor onError was called - possible polling issue");
				}
			}
		}, 15000);
	}

	@:timeout(2000)
	function testSecureSocket_LargeDataTransfer(async:Async) {
		var testComplete = false;
		var requestSent = false;

		socket.onConnect = function() {
			if (testComplete || requestSent)
				return;
			requestSent = true;

			// Send a request that should return a reasonably large response
			var request = "GET / HTTP/1.1\r\n";
			request += "Host: example.com\r\n";
			request += "Connection: close\r\n";
			request += "\r\n";

			socket.writeString(request);
			socket.flush();
		};

		var totalBytesReceived = 0;
		socket.onData = function(bytes) {
			if (testComplete)
				return;

			totalBytesReceived += bytes.length;

			// Read all available data
			if (socket.bytesAvailable > 0) {
				var data = socket.readUTFBytes();
				Assert.isTrue(data.length > 0);
			}
		};

		socket.onClose = function() {
			if (testComplete)
				return;
			testComplete = true;

			Assert.isTrue(totalBytesReceived > 500, 'Should have received substantial data (got $totalBytesReceived bytes)');
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Error: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}

	@:timeout(2000)
	function testSecureSocket_ReadAfterClose(async:Async) {
		var testComplete = false;

		socket.onConnect = function() {
			if (testComplete)
				return;
			testComplete = true;

			socket.close();

			// Try to read after closing
			var exceptionThrown = false;
			try {
				var bytes = Bytes.alloc(10);
				socket.readBytes(bytes);
			} catch (e:Exception) {
				exceptionThrown = true;
			}

			Assert.isTrue(exceptionThrown, 'Should throw exception when reading after close');
			async.done();
		};

		socket.onError = function(msg) {
			if (testComplete)
				return;
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				testComplete = true;
				Assert.fail('Connection failed: $msg');
				async.done();
			}
		};

		socket.connect("example.com", 443);
	}
}
