package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import hxSockets.Socket;
import haxe.io.Bytes;

/**
 * Tests for basic Socket functionality (non-network operations)
 */
class SocketBasicTests extends Test {
	
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
	
	// Initialization Tests
	
	function testSocket_NewInstance() {
		Assert.notNull(socket);
		Assert.isFalse(socket.connected);
		Assert.equals(0, socket.bytesAvailable);
		Assert.equals(20000, socket.timeout);
	}
	
	function testSocket_DefaultTimeout() {
		Assert.equals(20000, socket.timeout);
	}
	
	function testSocket_SetTimeout() {
		socket.timeout = 5000;
		Assert.equals(5000, socket.timeout);
		
		socket.timeout = 30000;
		Assert.equals(30000, socket.timeout);
	}
	
	function testSocket_InitialState() {
		Assert.isFalse(socket.connected);
		Assert.equals(0, socket.bytesAvailable);
		Assert.isNull(socket.localAddress);
		Assert.equals(0, socket.localPort);
		Assert.isNull(socket.remoteAddress);
		Assert.equals(0, socket.remotePort);
	}
	
	// Invalid Connection Parameters
	
	function testSocket_Connect_InvalidPort_Negative() {
		var errorCalled = false;
		socket.onError = function(msg) {
			errorCalled = true;
			Assert.isTrue(msg.indexOf("Invalid port") > -1);
		};
		
		socket.connect("localhost", -1);
		Assert.isTrue(errorCalled);
	}
	
	function testSocket_Connect_InvalidPort_TooHigh() {
		var errorCalled = false;
		socket.onError = function(msg) {
			errorCalled = true;
			Assert.isTrue(msg.indexOf("Invalid port") > -1);
		};
		
		socket.connect("localhost", 65536);
		Assert.isTrue(errorCalled);
	}
	
	function testSocket_Connect_InvalidHost() {
		var errorCalled = false;
		socket.onError = function(msg) {
			errorCalled = true;
			Assert.isTrue(msg.indexOf("Invalid host") > -1);
		};
		
		// Use an invalid hostname format
		socket.connect("", 80);
		Assert.isTrue(errorCalled);
	}
	
	// Multiple Connection Attempts
	
	function testSocket_Connect_AlreadyConnecting() {
		// First connection attempt
		socket.connect("example.com", 80);
		
		// Should close previous and start new connection
		socket.connect("google.com", 80);
		
		Assert.pass();
	}
	
	function testSocket_Close_NotConnected() {
		// Should not throw when closing an unconnected socket
		socket.close();
		Assert.pass();
	}
	
	function testSocket_Close_Multiple() {
		// Should handle multiple close calls gracefully
		socket.close();
		socket.close();
		socket.close();
		Assert.pass();
	}
	
	// Event Handler Tests
	
	function testSocket_EventHandlers_InitiallyNull() {
		var s = new Socket();
		Assert.isNull(s.onConnect);
		Assert.isNull(s.onClose);
		Assert.isNull(s.onData);
		Assert.isNull(s.onError);
	}
	
	function testSocket_EventHandlers_CanBeSet() {
		socket.onConnect = function() {};
		socket.onClose = function() {};
		socket.onData = function(b) {};
		socket.onError = function(e) {};
		
		Assert.notNull(socket.onConnect);
		Assert.notNull(socket.onClose);
		Assert.notNull(socket.onData);
		Assert.notNull(socket.onError);
	}
	
	// Bytes Operations (Buffer Tests)
	
	function testSocket_BytesAvailable_Initial() {
		Assert.equals(0, socket.bytesAvailable);
	}
	
	// Edge Cases
	
	function testSocket_ValidPortRange_Minimum() {
		var errorCalled = false;
		socket.onError = function(msg) {
			if (msg.indexOf("Invalid port") > -1) {
				errorCalled = true;
			}
		};
		
		socket.connect("localhost", 0);
		Assert.isFalse(errorCalled);
	}
	
	function testSocket_ValidPortRange_Maximum() {
		var errorCalled = false;
		socket.onError = function(msg) {
			if (msg.indexOf("Invalid port") > -1) {
				errorCalled = true;
			}
		};
		
		socket.connect("localhost", 65535);
		Assert.isFalse(errorCalled);
	}
	
	function testSocket_ValidPortRange_Common() {
		var ports = [80, 443, 8080, 3000, 5432, 3306];
		
		for (port in ports) {
			var s = new Socket();
			var errorCalled = false;
			s.onError = function(msg) {
				if (msg.indexOf("Invalid port") > -1) {
					errorCalled = true;
				}
			};
			
			s.connect("localhost", port);
			Assert.isFalse(errorCalled);
			s.close();
		}
	}
}