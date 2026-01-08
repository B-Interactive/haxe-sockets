package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import utest.Async;
import hxSockets.Socket;

/**
 * Tests for Socket network connections
 * These tests require actual network connectivity
 */
class SocketConnectionTests extends Test {
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

	// HTTP Connection Tests

	@:timeout(10000)
	function testSocket_Connect_HTTP(async:Async) {
		socket.timeout = 5000;

		socket.onConnect = function() {
			Assert.isTrue(socket.connected);
			Assert.notNull(socket.localAddress);
			Assert.isTrue(socket.localPort > 0);
			Assert.notNull(socket.remoteAddress);
			Assert.equals(80, socket.remotePort);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail('Connection failed: $msg');
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(10000)
	function testSocket_Connect_Timeout(async:Async) {
		socket.timeout = 1000; // 1 second timeout

		socket.onError = function(msg) {
			Assert.isTrue(msg.indexOf("timeout") > -1);
			Assert.isFalse(socket.connected);
			async.done();
		};

		socket.onConnect = function() {
			Assert.fail("Should not connect to non-routable address");
			async.done();
		};

		// Use a non-routable IP address that will timeout
		socket.connect("192.0.2.1", 80); // TEST-NET-1
	}

	@:timeout(10000)
	function testSocket_Connect_RefusedConnection(async:Async) {
		socket.timeout = 3000;

		socket.onError = function(msg) {
			Assert.isFalse(socket.connected);
			async.done();
		};

		socket.onConnect = function() {
			Assert.fail("Should not connect to closed port");
			async.done();
		};

		// Try to connect to a likely closed port on localhost
		socket.connect("localhost", 9); // Discard protocol port (usually closed)
	}

	@:timeout(10000)
	function testSocket_LocalHost_Connection(async:Async) {
		socket.timeout = 3000;

		var errorOccurred = false;
		socket.onError = function(msg) {
			errorOccurred = true;
			async.done();
		};

		socket.onConnect = function() {
			Assert.isTrue(socket.connected);
			socket.close();
			async.done();
		};

		// Attempt localhost connection
		// This may fail if no service is running, which is acceptable
		socket.connect("127.0.0.1", 80);
	}

	@:timeout(10000)
	function testSocket_Close_AfterConnect(async:Async) {
		socket.onConnect = function() {
			Assert.isTrue(socket.connected);
			socket.close();
			Assert.isFalse(socket.connected);
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail('Connection failed: $msg');
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(15000)
	function testSocket_Reconnect(async:Async) {
		var connectCount = 0;

		socket.onConnect = function() {
			connectCount++;

			if (connectCount == 1) {
				Assert.isTrue(socket.connected);
				socket.close();

				// Reconnect
				socket.connect("example.com", 80);
			} else if (connectCount == 2) {
				Assert.isTrue(socket.connected);
				socket.close();
				async.done();
			}
		};

		socket.onError = function(msg) {
			Assert.fail('Connection failed: $msg');
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(10000)
	function testSocket_OnClose_Event(async:Async) {
		var closeCalled = false;

		socket.onConnect = function() {
			Assert.isTrue(socket.connected);

			// Send invalid HTTP request to trigger server close
			socket.writeString("INVALID\r\n\r\n");
			socket.flush();
		};

		socket.onClose = function() {
			closeCalled = true;
			Assert.isFalse(socket.connected);
			async.done();
		};

		socket.onError = function(msg) {
			// Connection errors are acceptable, just end the test
			if (!closeCalled) {
				async.done();
			}
		};

		socket.connect("example.com", 80);
	}

	@:timeout(10000)
	function testSocket_IPv4_Connection(async:Async) {
		socket.onConnect = function() {
			Assert.isTrue(socket.connected);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail('Connection failed: $msg');
			async.done();
		};

		// Connect using IPv4 address
		socket.connect("93.184.216.34", 80); // example.com IP
	}

	@:timeout(10000)
	function testSocket_Properties_AfterConnect(async:Async) {
		socket.onConnect = function() {
			Assert.isTrue(socket.connected);
			Assert.equals(0, socket.bytesAvailable);

			// Local properties
			Assert.notNull(socket.localAddress);
			Assert.isTrue(socket.localPort > 0);

			// Remote properties
			Assert.notNull(socket.remoteAddress);
			Assert.equals(80, socket.remotePort);

			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail('Connection failed: $msg');
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(10000)
	function testSocket_CustomTimeout_Success(async:Async) {
		socket.timeout = 15000; // 15 seconds

		socket.onConnect = function() {
			Assert.isTrue(socket.connected);
			socket.close();
			async.done();
		};

		socket.onError = function(msg) {
			Assert.fail('Connection failed: $msg');
			async.done();
		};

		socket.connect("example.com", 80);
	}

	@:timeout(5000)
	function testSocket_CustomTimeout_Fast(async:Async) {
		socket.timeout = 500; // 500ms - very short

		socket.onError = function(msg) {
			Assert.isTrue(msg.indexOf("timeout") > -1);
			async.done();
		};

		socket.onConnect = function() {
			Assert.fail("Should timeout before connecting");
			async.done();
		};

		// Use a slow-responding address
		socket.connect("192.0.2.1", 80);
	}
}
