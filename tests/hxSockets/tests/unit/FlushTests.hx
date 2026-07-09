package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;
import hxSockets.tests.LocalServer;
import haxe.io.Bytes;

/**
 * Regression tests for Socket.flush() when there is no queued output.
 *
 * An event-driven owner (manual-poll or the internal Timer) calls flush() on
 * every tick, so flush() is frequently invoked with an empty output buffer.
 * A consuming getBytes() empties the buffer's backing storage, so flush() must
 * never consume an empty buffer and leave it unusable. The first case here
 * reproduced a null reference that only surfaced on the SECOND empty flush:
 * the first flush consumed the empty buffer, and the next flush dereferenced
 * the now-null backing storage.
 */
class FlushTests extends Test {
	function bytesOf(values:Array<Int>):Bytes {
		var b = Bytes.alloc(values.length);
		for (i in 0...values.length) {
			b.set(i, values[i]);
		}
		return b;
	}

	// Pump poll() until connected or the budget elapses.
	function pumpUntilConnected(socket:Socket, connectedRef:Array<Bool>, budget:Float):Void {
		var start = Sys.time();
		while (Sys.time() - start < budget && !connectedRef[0]) {
			socket.poll();
			Sys.sleep(0.005);
		}
	}

	/**
	 * Calling flush() repeatedly after connect with nothing queued must not
	 * throw. This is the exact production pattern: a poll loop flushes every
	 * tick while idle.
	 */
	@:timeout(8000)
	function testRepeatedEmptyFlushDoesNotThrow(async:Async) {
		var server = new LocalServer([], 0);
		server.start();

		var socket = new Socket(true); // manual poll, owner-driven flush
		var connected = [false];
		socket.onConnect = function() {
			connected[0] = true;
		};

		socket.connect("127.0.0.1", server.port);
		pumpUntilConnected(socket, connected, 4);
		Assert.isTrue(connected[0], "should connect once poll() is pumped");

		// Flush many times with no queued output. Before the fix the second
		// call threw "Null Object Reference" from BytesBuffer.getBytes().
		var threw = false;
		try {
			for (_ in 0...10) {
				socket.flush();
			}
		} catch (e:Dynamic) {
			threw = true;
		}
		Assert.isFalse(threw, "repeated empty flush() must not throw");

		socket.close();
		server.stop();
		async.done();
	}

	/**
	 * A write + flush, followed by further empty flushes, then another write +
	 * flush must all succeed. This proves the output buffer stays usable after
	 * being consumed and after empty flushes.
	 */
	@:timeout(8000)
	function testWriteThenEmptyFlushesThenWriteAgain(async:Async) {
		var server = new LocalServer([], 0);
		server.start();

		var socket = new Socket(true);
		var connected = [false];
		socket.onConnect = function() {
			connected[0] = true;
		};

		socket.connect("127.0.0.1", server.port);
		pumpUntilConnected(socket, connected, 4);
		Assert.isTrue(connected[0], "should connect once poll() is pumped");

		var threw = false;
		try {
			// Queue and flush some bytes (consumes the buffer).
			socket.writeBytes(bytesOf([1, 2, 3, 4]));
			socket.flush();
			// Idle empty flushes on the just-consumed buffer.
			for (_ in 0...5) {
				socket.flush();
			}
			// Buffer must still accept and flush new output.
			socket.writeBytes(bytesOf([5, 6, 7, 8]));
			socket.flush();
			for (_ in 0...5) {
				socket.flush();
			}
		} catch (e:Dynamic) {
			threw = true;
		}
		Assert.isFalse(threw, "write / empty-flush / write cycle must not throw");

		socket.close();
		server.stop();
		async.done();
	}
}
