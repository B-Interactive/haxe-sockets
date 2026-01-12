package hxSockets.tests.unit;

import haxe.Exception;
import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;
import haxe.io.Bytes;

/**
 * Tests for Socket data transfer operations
 */
class SocketDataTransferTests extends Test {
	var socket:Socket;

	function setup() {
		socket = new Socket();
	}

	function teardown() {
		if (socket != null && socket.connected) {
			socket.close();
		}
		socket = null;
	}

	// HTTP Request/Response Tests

	@:timeout(15000)
	function testSocket_SendHTTP_ReceiveData(async:Async) {
		socket.timeout = 10000;

		socket.onConnect = function() {
			var request = "GET / HTTP/1.1\r\n";
			request += "Host: example.com\r\n";
			request += "Connection: close\r\n";
			request += "\r\n";

			socket.writeString(request);
			socket.flush();
		};

		socket.onData = function(bytes) {
			Assert.isTrue(socket.bytesAvailable > 0);

			var response = socket.readUTFBytes();
			Assert.isTrue(response.length > 0);
			Assert.isTrue(response.indexOf("HTTP/") > -1);

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_WriteBytes_Basic(async:Async) {
		socket.onConnect = function() {
			var data = Bytes.ofString("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
			socket.writeBytes(data);
			socket.flush();
		};

		socket.onData = function(bytes) {
			Assert.isTrue(socket.bytesAvailable > 0);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_WriteBytes_WithOffset(async:Async) {
		socket.onConnect = function() {
			var data = Bytes.ofString("XXXGET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
			// Skip the first 3 bytes ("XXX")
			socket.writeBytes(data, 3);
			socket.flush();
		};

		socket.onData = function(bytes) {
			Assert.isTrue(socket.bytesAvailable > 0);
			var response = socket.readUTFBytes();
			Assert.isTrue(response.indexOf("HTTP/") > -1);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_WriteBytes_WithLength(async:Async) {
		socket.onConnect = function() {
			var fullData = Bytes.ofString("GET / HTTP/1.1\r\nHost: example.com\r\n\r\nEXTRA");
			var correctLength = fullData.length - 5; // Exclude "EXTRA"
			socket.writeBytes(fullData, 0, correctLength);
			socket.flush();
		};

		socket.onData = function(bytes) {
			Assert.isTrue(socket.bytesAvailable > 0);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_ReadString_Partial(async:Async) {
		socket.onConnect = function() {
			socket.writeString("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
			socket.flush();
		};

		var dataReceived = false;
		socket.onData = function(bytes) {
			if (!dataReceived) {
				dataReceived = true;

				var available = socket.bytesAvailable;
				if (available > 10) {
					// Read only first 10 bytes
					var partial = socket.readUTFBytes(10);
					Assert.equals(10, partial.length);

					// Should still have data available
					Assert.isTrue(socket.bytesAvailable > 0);
					Assert.equals(available - 10, socket.bytesAvailable);
				}

				socket.close();
				async.done();
			}
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_ReadAllBytes(async:Async) {
		socket.onConnect = function() {
			socket.writeString("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
			socket.flush();
		};

		var dataReceived = false;
		socket.onData = function(bytes) {
			if (!dataReceived) {
				dataReceived = true;

				var available = socket.bytesAvailable;
				var all = socket.readAllBytes();

				Assert.equals(available, all.length);
				Assert.equals(0, socket.bytesAvailable);

				socket.close();
				async.done();
			}
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_ReadBytes_IntoBuffer(async:Async) {
		socket.onConnect = function() {
			socket.writeString("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
			socket.flush();
		};

		var dataReceived = false;
		socket.onData = function(bytes) {
			if (!dataReceived) {
				dataReceived = true;

				if (socket.bytesAvailable >= 20) {
					var buffer = Bytes.alloc(20);
					socket.readBytes(buffer, 0, 20);

					Assert.equals(20, buffer.length);
					Assert.notNull(buffer);

					socket.close();
					async.done();
				}
			}
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_MultipleWrites_BeforeFlush(async:Async) {
		socket.onConnect = function() {
			// Write in multiple parts
			socket.writeString("GET / HTTP/1.1\r\n");
			socket.writeString("Host: example.com\r\n");
			socket.writeString("Connection: close\r\n");
			socket.writeString("\r\n");

			// Single flush
			socket.flush();
		};

		socket.onData = function(bytes) {
			Assert.isTrue(socket.bytesAvailable > 0);
			var response = socket.readUTFBytes();
			Assert.isTrue(response.indexOf("HTTP/") > -1);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_BytesAvailable_Updates(async:Async) {
		socket.onConnect = function() {
			socket.writeString("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
			socket.flush();
		};

		var dataReceived = false;
		socket.onData = function(bytes) {
			if (!dataReceived) {
				dataReceived = true;

				var initial = socket.bytesAvailable;
				Assert.isTrue(initial > 0);

				// Read some data
				if (initial >= 10) {
					socket.readUTFBytes(5);
					Assert.equals(initial - 5, socket.bytesAvailable);

					socket.readUTFBytes(5);
					Assert.equals(initial - 10, socket.bytesAvailable);
				}

				socket.close();
				async.done();
			}
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_EmptyRead(async:Async) {
		socket.onConnect = function() {
			// Don't send anything, just check empty buffer
			Assert.raises(function() {
				socket.readUTFBytes();
			}, Exception);

			Assert.raises(function() {
				socket.readAllBytes();
			}, Exception);

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_BinaryData(async:Async) {
		socket.onConnect = function() {
			// Create binary data
			var data = Bytes.alloc(256);
			for (i in 0...256) {
				data.set(i, i);
			}

			// Verify we can write binary data
			socket.writeBytes(data);
			socket.flush();

			// Assert that we successfully wrote the data
			Assert.isTrue(socket.connected);
			Assert.equals(256, data.length);

			// Close after a moment
			haxe.Timer.delay(function() {
				socket.close();
				async.done();
			}, 100);
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_UTF8_Encoding(async:Async) {
		socket.onConnect = function() {
			var utf8String = "Hello 世界 🌍";
			socket.writeString(utf8String);
			socket.flush();

			// Assert that we're connected and the string is valid
			Assert.isTrue(socket.connected);
			Assert.isTrue(utf8String.length > 0);

			// Close after a moment
			haxe.Timer.delay(function() {
				socket.close();
				async.done();
			}, 100);
		};

		socket.onError = function(msg) {
			Assert.fail(msg);
			async.done();
		};

		socket.connect("example.com", 80);
	}
}
