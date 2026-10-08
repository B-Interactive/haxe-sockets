package hxSockets.tests.unit;

import haxe.Exception;
import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;
import hxSockets.SecureSocket;
#if (cpp || neko || hl)
import hxSockets.tests.LocalServer;
import hxSockets.tests.SilentServer;
#end
import haxe.io.Bytes;

/**
 * Tests for the configurable receive maximum and the capped outbound buffer
 * on Socket (and inherited by SecureSocket).
 */
class BufferCapTests extends Test {
	static final MIB = 1024 * 1024;

	function bytesOfLength(size:Int):Bytes {
		var b = Bytes.alloc(size);
		for (i in 0...size) {
			b.set(i, i % 256);
		}
		return b;
	}

	// Defaults and round-trip (no network required)

	function testSocket_DefaultBufferCaps() {
		var socket = new Socket(true);
		Assert.equals(16 * MIB, socket.maxReceiveBuffer);
		Assert.equals(16 * MIB, socket.maxSendBuffer);
		Assert.equals(Socket.DEFAULT_MAX_BUFFER_BYTES, socket.maxReceiveBuffer);
		Assert.equals(Socket.DEFAULT_MAX_BUFFER_BYTES, socket.maxSendBuffer);
		Assert.equals(0, socket.bytesPending);
	}

	function testSocket_ReceiveMaxRoundTrip() {
		var socket = new Socket(true);
		socket.maxReceiveBuffer = 64;
		Assert.equals(64, socket.maxReceiveBuffer);
		socket.maxReceiveBuffer = 2 * MIB;
		Assert.equals(2 * MIB, socket.maxReceiveBuffer);
	}

	function testSocket_SendMaxRoundTrip() {
		var socket = new Socket(true);
		socket.maxSendBuffer = 128;
		Assert.equals(128, socket.maxSendBuffer);
		socket.maxSendBuffer = 8 * MIB;
		Assert.equals(8 * MIB, socket.maxSendBuffer);
	}

	function testSocket_ReceiveMaxRejectsInvalid() {
		var socket = new Socket(true);
		Assert.raises(function() socket.maxReceiveBuffer = 0, Exception);
		Assert.raises(function() socket.maxReceiveBuffer = -1, Exception);
	}

	function testSocket_SendMaxRejectsInvalid() {
		var socket = new Socket(true);
		Assert.raises(function() socket.maxSendBuffer = 0, Exception);
		Assert.raises(function() socket.maxSendBuffer = -1, Exception);
	}

	function testSecureSocket_InheritsCaps() {
		var socket = new SecureSocket(true);
		Assert.equals(Socket.DEFAULT_MAX_BUFFER_BYTES, socket.maxReceiveBuffer);
		Assert.equals(Socket.DEFAULT_MAX_BUFFER_BYTES, socket.maxSendBuffer);
		socket.maxSendBuffer = 256;
		Assert.equals(256, socket.maxSendBuffer);
	}

	function testCapsSurviveClose() {
		var socket = new Socket(true);
		socket.maxReceiveBuffer = 64;
		socket.maxSendBuffer = 96;
		socket.close();
		Assert.equals(64, socket.maxReceiveBuffer);
		Assert.equals(96, socket.maxSendBuffer);
	}

	#if (cpp || neko || hl)
	// Pump poll() until connected or the budget elapses.
	function pumpUntilConnected(socket:Socket, connectedRef:Array<Bool>, budget:Float):Void {
		var start = Sys.time();
		while (Sys.time() - start < budget && !connectedRef[0]) {
			socket.poll();
			Sys.sleep(0.005);
		}
	}

	/**
	 * Writes past the send cap throw and queue nothing; a successful flush
	 * reduces bytesPending so later writes fit again.
	 */
	@:timeout(8000)
	function testSendCapThrowsPastCap(async:Async) {
		var server = new SilentServer();
		server.start();

		var socket = new Socket(true);
		var connected = [false];
		socket.onConnect = function() {
			connected[0] = true;
		};
		socket.connect("127.0.0.1", server.port);
		pumpUntilConnected(socket, connected, 4);
		Assert.isTrue(connected[0], "should connect once poll() is pumped");

		socket.maxSendBuffer = 32;
		socket.writeBytes(bytesOfLength(16));
		Assert.equals(16, socket.bytesPending);

		// 16 + 20 would exceed the 32-byte cap: throws and queues nothing.
		var threw = false;
		try {
			socket.writeBytes(bytesOfLength(20));
		} catch (e:Exception) {
			threw = true;
		}
		Assert.isTrue(threw, "write past the send cap must throw");
		Assert.equals(16, socket.bytesPending, "rejected write must not queue bytes");

		// Lowering the cap below bytesPending is refused.
		Assert.raises(function() socket.maxSendBuffer = 8, Exception);

		// Once flushed out, the full cap is available again.
		socket.flush();
		Assert.equals(0, socket.bytesPending, "flushed bytes must leave the queue");
		socket.writeBytes(bytesOfLength(32)); // exactly at the cap
		Assert.equals(32, socket.bytesPending);
		Assert.raises(function() socket.writeBytes(bytesOfLength(1)), Exception);
		socket.flush();
		Assert.equals(0, socket.bytesPending);

		socket.close();
		server.stop();
		async.done();
	}

	/**
	 * writeString shares the same cap and throws past it.
	 */
	@:timeout(8000)
	function testWriteStringRespectsSendCap(async:Async) {
		var server = new SilentServer();
		server.start();

		var socket = new Socket(true);
		var connected = [false];
		socket.onConnect = function() {
			connected[0] = true;
		};
		socket.connect("127.0.0.1", server.port);
		pumpUntilConnected(socket, connected, 4);
		Assert.isTrue(connected[0], "should connect once poll() is pumped");

		socket.maxSendBuffer = 4;
		socket.writeString("abcd"); // exactly at the cap (UTF-8, ASCII)
		var threw = false;
		try {
			socket.writeString("e");
		} catch (e:Exception) {
			threw = true;
		}
		Assert.isTrue(threw, "writeString past the send cap must throw");
		Assert.equals(4, socket.bytesPending);

		socket.close();
		server.stop();
		async.done();
	}

	/**
	 * A lowered receive max holds: reads never exceed it, and data keeps
	 * arriving as the application drains the buffer.
	 */
	@:timeout(10000)
	function testReceiveMaxCapsBufferedBytes(async:Async) {
		var server = new LocalServer([bytesOfLength(64), bytesOfLength(64)], 10);
		server.start();

		var socket = new Socket(true);
		var connected = [false];
		socket.onConnect = function() {
			connected[0] = true;
		};
		socket.maxReceiveBuffer = 64;
		socket.connect("127.0.0.1", server.port);
		pumpUntilConnected(socket, connected, 4);
		Assert.isTrue(connected[0], "should connect once poll() is pumped");

		var total = 0;
		var start = Sys.time();
		while (Sys.time() - start < 6 && total < 128) {
			socket.poll();
			Assert.isTrue(socket.bytesAvailable <= 64, "buffered bytes must never exceed maxReceiveBuffer");
			if (socket.bytesAvailable > 0) {
				var drained = socket.readExactly(socket.bytesAvailable);
				if (drained != null) {
					total += drained.length;
				}
			}
			Sys.sleep(0.005);
		}
		Assert.equals(128, total, "draining must let the capped buffer receive everything");

		socket.close();
		server.stop();
		async.done();
	}
	#end
}
