package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;
import hxSockets.tests.LocalServer;
import haxe.io.Bytes;

/**
 * Tests manual-poll mode: with the internal Timer disabled the socket makes no
 * progress unless poll() is called, and connects + receives when poll() is
 * pumped.
 */
class ManualPollTests extends Test {
	function bytesOf(values:Array<Int>):Bytes {
		var b = Bytes.alloc(values.length);
		for (i in 0...values.length) {
			b.set(i, values[i]);
		}
		return b;
	}

	@:timeout(8000)
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
}
