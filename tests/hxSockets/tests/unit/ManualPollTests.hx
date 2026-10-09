package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;
import hxSockets.tests.LocalServer;
import hxSockets.tests.TestHelpers;
import haxe.io.Bytes;
import haxe.Exception;

/**
 * Tests manual-poll mode: with the internal Timer disabled the socket makes no
 * progress unless poll() is called, and connects + receives when poll() is
 * pumped.
 *
 * Loopback-only (offline path); the class-level timeout exceeds the library
 * default `Socket.timeout` so utest never aborts before the socket could.
 */
@:timeout(TestHelpers.SOCKET_TEST_TIMEOUT)
class ManualPollTests extends Test {
	function bytesOf(values:Array<Int>):Bytes {
		var b = Bytes.alloc(values.length);
		for (i in 0...values.length) {
			b.set(i, values[i]);
		}
		return b;
	}

	function testNoProgressWithoutPoll(async:Async) {
		var server = new LocalServer([bytesOf([1, 2, 3, 4])], 0);
		server.start();

		var socket = new Socket(true); // manual poll, no internal Timer
		var connected = false;
		socket.onConnect = function() {
			connected = true;
		};

		socket.connect("127.0.0.1", server.port);

		// Without poll(), the socket must not advance on its own.
		Sys.sleep(0.3);
		Assert.isFalse(connected, "manual-poll socket must not connect without poll()");
		Assert.equals(0, socket.bytesAvailable);

		// Pump poll(); it should now connect and receive.
		var start = Sys.time();
		while (Sys.time() - start < 4 && (!connected || !socket.hasAvailable(4))) {
			socket.poll();
			Sys.sleep(0.005);
		}
		Assert.isTrue(connected, "should connect once poll() is pumped");
		Assert.isTrue(socket.hasAvailable(4), "should receive data once poll() is pumped");

		var data = socket.readExactly(4);
		Assert.notNull(data);
		Assert.equals(1, data.get(0));
		Assert.equals(4, data.get(3));

		socket.close();
		server.stop();
		async.done();
	}

	function testCloseIsIdempotent() {
		var socket = new Socket(true);
		// close() is safe when never connected.
		socket.close();
		socket.close();
		Assert.isFalse(socket.connected);
	}

	/**
	 * poll() called from inside a callback runs within the active tick and is
	 * ignored: no re-entry, no stack overflow, and buffered bytes are neither
	 * consumed early nor delivered twice.
	 */
	function testNestedPollFromCallbackIsIgnored() {
		var server = new LocalServer([bytesOf([1, 2, 3, 4])], 0);
		server.start();

		var socket = new Socket(true);
		var dataCount = 0;
		var connected = false;
		socket.onConnect = function() {
			connected = true;
			// A poll from within the tick must be a no-op.
			socket.poll();
		};
		socket.onData = function(_) {
			dataCount++;
			// A tight burst of nested polls stays ignored rather than re-entering.
			for (i in 0...100) {
				socket.poll();
			}
		};

		socket.connect("127.0.0.1", server.port);
		var start = Sys.time();
		while (Sys.time() - start < 4 && dataCount == 0) {
			socket.poll();
			Sys.sleep(0.005);
		}

		Assert.isTrue(connected, "should connect despite the ignored nested poll");
		Assert.isTrue(dataCount > 0, "data should arrive while poll() is pumped");
		Assert.equals(4, socket.bytesAvailable, "nested poll must not consume or duplicate buffered bytes");

		socket.close();
		server.stop();
	}

	/**
	 * A callback that throws must not abort the tick or future ticks: polling
	 * continues after the throw and the peer-close still reaches onClose.
	 */
	function testThrowingCallbackDoesNotStopPolling() {
		var server = new LocalServer([bytesOf([1, 2, 3, 4]), bytesOf([5, 6])], 20);
		server.start();

		var socket = new Socket(true);
		var connected = false;
		var closeCount = 0;
		socket.onConnect = function() {
			connected = true;
		};
		socket.onData = function(_) {
			throw new Exception("callback failure");
		};
		socket.onClose = function() {
			closeCount++;
		};

		socket.connect("127.0.0.1", server.port);
		var start = Sys.time();
		while (Sys.time() - start < 4 && closeCount == 0) {
			socket.poll();
			Sys.sleep(0.005);
		}

		Assert.isTrue(connected, "connect should complete despite the throwing onData");
		Assert.equals(1, closeCount, "polling survives the throwing callback and delivers onClose");
		Assert.isFalse(socket.connected, "peer close tears the socket down normally");

		socket.close();
		server.stop();
	}
}
