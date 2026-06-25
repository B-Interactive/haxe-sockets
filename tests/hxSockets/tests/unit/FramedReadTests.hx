package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;
import hxSockets.tests.LocalServer;
import haxe.io.Bytes;

/**
 * Tests for the partial-read helpers readExactly(N), peekBytes(N) and
 * hasAvailable(N). Data arrives in small chunks from a loopback server and the
 * socket is driven in manual-poll mode to check there is no over-read.
 */
class FramedReadTests extends Test {
	function bytesOf(values:Array<Int>):Bytes {
		var b = Bytes.alloc(values.length);
		for (i in 0...values.length) {
			b.set(i, values[i]);
		}
		return b;
	}

	// Pump poll() until the condition holds or the time budget expires.
	function pumpUntil(socket:Socket, condition:Void->Bool, budgetSeconds:Float):Bool {
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

	@:timeout(8000)
	function testReadExactlyAcrossChunks(async:Async) {
		// A 10-byte frame split across three chunks.
		var server = new LocalServer([bytesOf([0, 1, 2]), bytesOf([3, 4, 5, 6]), bytesOf([7, 8, 9])], 30);
		server.start();

		var socket = new Socket(true); // manual poll
		var connected = false;
		socket.onConnect = function() {
			connected = true;
		};
		socket.onError = function(msg) {
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				Assert.fail('Unexpected error: $msg');
				server.stop();
				async.done();
			}
		};

		socket.connect("127.0.0.1", server.port);

		var gotConnect = pumpUntil(socket, function() return connected, 4);
		Assert.isTrue(gotConnect, "should connect to local server");

		// Before all 10 bytes arrive, readExactly(10) must return null.
		var nullWhilePartial = pumpUntil(socket, function() {
			return socket.bytesAvailable > 0 && socket.bytesAvailable < 10 && socket.readExactly(10) == null;
		}, 4);
		Assert.isTrue(nullWhilePartial, "readExactly should return null until all 10 bytes arrive");

		// Once all 10 are present, readExactly returns them.
		var full:Bytes = null;
		var gotFull = pumpUntil(socket, function() {
			full = socket.readExactly(10);
			return full != null;
		}, 4);
		Assert.isTrue(gotFull, "readExactly(10) should eventually succeed");
		Assert.equals(10, full.length);
		for (i in 0...10) {
			Assert.equals(i, full.get(i));
		}
		// No over-read.
		Assert.equals(0, socket.bytesAvailable);

		socket.close();
		server.stop();
		async.done();
	}

	@:timeout(8000)
	function testPeekDoesNotConsume(async:Async) {
		var server = new LocalServer([bytesOf([0xAA, 0xBB, 0xCC, 0xDD])], 0);
		server.start();

		var socket = new Socket(true);
		var connected = false;
		socket.onConnect = function() {
			connected = true;
		};
		socket.onError = function(msg) {
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				Assert.fail('Unexpected error: $msg');
				server.stop();
				async.done();
			}
		};

		socket.connect("127.0.0.1", server.port);
		pumpUntil(socket, function() return connected, 4);

		var haveFour = pumpUntil(socket, function() return socket.hasAvailable(4), 4);
		Assert.isTrue(haveFour, "should buffer 4 bytes");

		// Peek twice; must be identical and non-consuming.
		var p1 = socket.peekBytes(4);
		var p2 = socket.peekBytes(4);
		Assert.notNull(p1);
		Assert.notNull(p2);
		Assert.equals(4, socket.bytesAvailable);
		for (i in 0...4) {
			Assert.equals(p1.get(i), p2.get(i));
		}

		// Beyond what is buffered: hasAvailable is false and peek returns null.
		Assert.isFalse(socket.hasAvailable(5));
		Assert.isNull(socket.peekBytes(5));

		// Consume and verify it matches the peeked content.
		var consumed = socket.readExactly(4);
		Assert.equals(0xAA, consumed.get(0));
		Assert.equals(0xDD, consumed.get(3));
		Assert.equals(0, socket.bytesAvailable);

		socket.close();
		server.stop();
		async.done();
	}

	@:timeout(8000)
	function testTwoBackToBackFramesNoOverRead(async:Async) {
		// Two 4-byte frames in one chunk; reading the first must not consume
		// the second.
		var server = new LocalServer([bytesOf([1, 2, 3, 4, 5, 6, 7, 8])], 0);
		server.start();

		var socket = new Socket(true);
		var connected = false;
		socket.onConnect = function() {
			connected = true;
		};
		socket.onError = function(msg) {
			if (msg.indexOf("Blocked") == -1 && msg.indexOf("Blocking") == -1) {
				Assert.fail('Unexpected error: $msg');
				server.stop();
				async.done();
			}
		};

		socket.connect("127.0.0.1", server.port);
		pumpUntil(socket, function() return connected, 4);
		pumpUntil(socket, function() return socket.hasAvailable(8), 4);

		var first = socket.readExactly(4);
		Assert.notNull(first);
		Assert.equals(1, first.get(0));
		Assert.equals(4, first.get(3));
		Assert.equals(4, socket.bytesAvailable); // second frame untouched

		var second = socket.readExactly(4);
		Assert.notNull(second);
		Assert.equals(5, second.get(0));
		Assert.equals(8, second.get(3));
		Assert.equals(0, socket.bytesAvailable);

		socket.close();
		server.stop();
		async.done();
	}
}
