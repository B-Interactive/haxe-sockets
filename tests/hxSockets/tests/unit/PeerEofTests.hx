package hxSockets.tests.unit;

import haxe.io.Bytes;
import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;
import hxSockets.tests.LocalServer;
import hxSockets.tests.TestHelpers;

/**
 * Tests the peer-EOF callback contract: a clean peer close tears the socket
 * down and fires onClose only. onError and onErrorKind are reserved for
 * faults and must not fire on this path.
 *
 * Loopback-only (offline path); the class-level timeout exceeds the library
 * default `Socket.timeout` so utest never aborts before the socket could.
 */
@:timeout(TestHelpers.SOCKET_TEST_TIMEOUT)
class PeerEofTests extends Test {
	function testCleanPeerCloseFiresOnCloseOnly(async:Async) {
		// The server accepts, sends nothing and closes: a clean peer EOF.
		var server = new LocalServer([], 0);
		server.start();

		var socket = new Socket(true); // manual poll
		var closeCount = 0;
		var errorCount = 0;
		var kindCount = 0;

		socket.onClose = function() {
			closeCount++;
			Assert.isFalse(socket.connected, "the socket must be torn down before onClose fires");
		};
		socket.onError = function(msg) {
			errorCount++;
		};
		socket.onErrorKind = function(kind, msg) {
			kindCount++;
		};

		socket.connect("127.0.0.1", server.port);

		var start = Sys.time();
		while (Sys.time() - start < 8 && closeCount == 0 && errorCount == 0) {
			socket.poll();
			Sys.sleep(0.005);
		}

		Assert.equals(0, errorCount, "a clean peer close must not fire onError");
		Assert.equals(1, closeCount, "clean peer close should fire onClose once");

		// Keep pumping briefly to confirm no error callbacks arrive late.
		var extra = Sys.time() + 0.2;
		while (Sys.time() < extra) {
			socket.poll();
			Sys.sleep(0.005);
		}

		Assert.equals(0, kindCount, "a clean peer close must not fire onErrorKind");
		Assert.isFalse(socket.connected, "the socket must be torn down after peer EOF");

		socket.close();
		server.stop();
		async.done();
	}

	function testDataThenCleanCloseFiresOnCloseOnly(async:Async) {
		// The server streams a chunk then closes; the client drains the data
		// first so the EOF check is not racing buffered bytes.
		var server = new LocalServer([Bytes.ofString("BYE")], 0);
		server.start();

		var socket = new Socket(true);
		var gotData = false;
		var closeCount = 0;
		var errorCount = 0;
		var kindCount = 0;

		socket.onData = function(chunk) {
			gotData = true;
		};
		socket.onClose = function() {
			closeCount++;
		};
		socket.onError = function(msg) {
			errorCount++;
		};
		socket.onErrorKind = function(kind, msg) {
			kindCount++;
		};

		socket.connect("127.0.0.1", server.port);

		var start = Sys.time();
		while (Sys.time() - start < 8 && closeCount == 0 && errorCount == 0) {
			socket.poll();
			if (socket.bytesAvailable > 0) {
				socket.readAllBytes();
			}
			Sys.sleep(0.005);
		}

		Assert.isTrue(gotData, "the chunk should arrive before the peer closes");
		Assert.equals(0, errorCount, "a clean peer close must not fire onError");
		Assert.equals(0, kindCount, "a clean peer close must not fire onErrorKind");
		Assert.equals(1, closeCount, "clean peer close should fire onClose once");
		Assert.isFalse(socket.connected, "the socket must be torn down after peer EOF");

		socket.close();
		server.stop();
		async.done();
	}
}
