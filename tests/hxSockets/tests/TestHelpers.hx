package hxSockets.tests;

import haxe.io.Bytes;
import utest.Assert;
import utest.Async;

/**
 * Helper utilities for socket tests
 */
class TestHelpers {
	/**
	 * utest `@:timeout` budget for internet-facing tests: covers the library
	 * default `Socket.timeout` (20 s) plus slack for DNS, TLS handshake and
	 * poll latency, so utest never aborts before the socket times out itself.
	 */
	public static inline var SOCKET_TEST_TIMEOUT:Int = 25000;

	static var _internet:Null<Bool>;

	/**
	 * Check if we have internet connectivity (cached; one DNS attempt per run)
	 */
	public static function hasInternetConnection():Bool {
		if (_internet == null) {
			// Simple heuristic - attempt to resolve a known host
			try {
				new sys.net.Host("example.com");
				_internet = true;
			} catch (e:Dynamic) {
				_internet = false;
			}
		}
		return _internet;
	}

	/**
	 * True when internet-dependent tests should skip: forced with `-D offline`
	 * at compile time, or when connectivity cannot be detected at run time.
	 */
	public static function internetUnavailable():Bool {
		#if offline
		return true;
		#else
		return !hasInternetConnection();
		#end
	}

	/**
	 * Skip an internet-dependent test when the network is unavailable: traces
	 * the reason, passes cleanly (warnings would turn an offline CI run red),
	 * resolves `async`, and returns `true` so the caller can `return`.
	 */
	public static function skipInternetTest(async:Async):Bool {
		if (!internetUnavailable()) {
			return false;
		}
		trace("SKIPPED: no internet - skipping internet-dependent test");
		Assert.pass();
		async.done();
		return true;
	}

	/**
	 * Check if a local port is available
	 */
	public static function isPortAvailable(port:Int):Bool {
		try {
			var socket = new sys.net.Socket();
			socket.bind(new sys.net.Host("127.0.0.1"), port);
			socket.close();
			return true;
		} catch (e:Dynamic) {
			return false;
		}
	}

	/**
	 * Create test binary data
	 */
	public static function createTestBytes(size:Int):Bytes {
		var bytes = Bytes.alloc(size);
		for (i in 0...size) {
			bytes.set(i, i % 256);
		}
		return bytes;
	}

	/**
	 * Verify bytes are equal
	 */
	public static function bytesEqual(a:Bytes, b:Bytes):Bool {
		if (a.length != b.length)
			return false;
		for (i in 0...a.length) {
			if (a.get(i) != b.get(i))
				return false;
		}
		return true;
	}

	/**
	 * Create a simple HTTP GET request
	 */
	public static function createHTTPGetRequest(host:String, path:String = "/"):String {
		var request = 'GET $path HTTP/1.1\r\n';
		request += 'Host: $host\r\n';
		request += 'Connection: close\r\n';
		request += '\r\n';
		return request;
	}

	/**
	 * Parse HTTP response status code
	 */
	public static function parseHTTPStatusCode(response:String):Int {
		var lines = response.split("\r\n");
		if (lines.length > 0) {
			var statusLine = lines[0];
			var parts = statusLine.split(" ");
			if (parts.length >= 2) {
				return Std.parseInt(parts[1]);
			}
		}
		return -1;
	}

	/**
	 * Check if response is valid HTTP
	 */
	public static function isValidHTTPResponse(response:String):Bool {
		return response.indexOf("HTTP/") == 0;
	}

	/**
	 * Extract headers from HTTP response
	 */
	public static function extractHTTPHeaders(response:String):Map<String, String> {
		var headers = new Map<String, String>();
		var headerEnd = response.indexOf("\r\n\r\n");

		if (headerEnd > 0) {
			var headerSection = response.substr(0, headerEnd);
			var lines = headerSection.split("\r\n");

			// Skip status line
			for (i in 1...lines.length) {
				var line = lines[i];
				var colonPos = line.indexOf(":");
				if (colonPos > 0) {
					var key = line.substr(0, colonPos).toLowerCase();
					var value = StringTools.trim(line.substr(colonPos + 1));
					headers.set(key, value);
				}
			}
		}

		return headers;
	}

	/**
	 * Wait for a condition with timeout
	 */
	public static function waitFor(condition:Void->Bool, timeoutMs:Int, onSuccess:Void->Void, onTimeout:Void->Void):Void {
		var startTime = Sys.time();
		var timer = new haxe.Timer(50);

		timer.run = function() {
			if (condition()) {
				timer.stop();
				onSuccess();
			} else if ((Sys.time() - startTime) * 1000 > timeoutMs) {
				timer.stop();
				onTimeout();
			}
		};
	}

	/**
	 * Get a list of common test hosts for network tests
	 */
	public static function getTestHosts():Array<{host:String, port:Int}> {
		return [
			{host: "example.com", port: 80},
			{host: "www.google.com", port: 443},
			{host: "www.github.com", port: 443}
		];
	}

	/**
	 * Simple string sanitization for display
	 */
	public static function sanitizeForDisplay(str:String, maxLength:Int = 100):String {
		if (str.length > maxLength) {
			return str.substr(0, maxLength) + "...";
		}
		return str;
	}
}
