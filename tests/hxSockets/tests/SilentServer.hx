package hxSockets.tests;

import sys.net.Host;
import sys.net.Socket as SysSocket;
import sys.thread.Thread;

/**
 * A tiny loopback TCP server that accepts one client and then stays silent,
 * so a TLS client's handshake keeps blocking. Runs on its own thread and
 * holds the connection open until stop() is called.
 */
class SilentServer {
	public var port(default, null):Int;

	var _listener:SysSocket;
	var _client:SysSocket;
	var _running:Bool = true;

	public function new() {
		port = _bindEphemeral();
	}

	function _bindEphemeral():Int {
		// Try ports until one binds.
		var p = 0;
		var attempt = 49400;
		while (p == 0 && attempt < 49600) {
			try {
				var s = new SysSocket();
				s.bind(new Host("127.0.0.1"), attempt);
				s.listen(1);
				_listener = s;
				p = attempt;
			} catch (e:Dynamic) {
				attempt++;
			}
		}
		if (p == 0) {
			throw "SilentServer: could not bind a loopback port";
		}
		return p;
	}

	/**
	 * Accept the first client on a background thread and send nothing.
	 */
	public function start():Void {
		Thread.create(function() {
			try {
				_client = _listener.accept();
				while (_running) {
					Sys.sleep(0.02);
				}
			} catch (e:Dynamic) {
				// Listener closed before a client arrived; the test drives its own assertions.
			}
		});
	}

	public function stop():Void {
		_running = false;
		if (_client != null) {
			try {
				_client.close();
			} catch (e:Dynamic) {}
			_client = null;
		}
		if (_listener != null) {
			try {
				_listener.close();
			} catch (e:Dynamic) {}
			_listener = null;
		}
	}
}
