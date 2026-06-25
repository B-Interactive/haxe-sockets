package hxSockets.tests;

import haxe.io.Bytes;
import sys.net.Host;
import sys.net.Socket as SysSocket;
import sys.thread.Thread;

/**
 * A tiny loopback TCP server for socket tests. Accepts one client on a
 * 127.0.0.1 port and serves a scripted sequence of byte chunks (with optional
 * delays) so tests can exercise chunked reads. Runs on its own thread.
 */
class LocalServer {
	public var port(default, null):Int;

	var _listener:SysSocket;
	var _chunks:Array<Bytes>;
	var _delayMs:Int;
	var _running:Bool = true;

	public function new(chunks:Array<Bytes>, delayMs:Int = 20) {
		_chunks = chunks;
		_delayMs = delayMs;
		port = _bindEphemeral();
	}

	function _bindEphemeral():Int {
		// Try ports until one binds.
		var p = 0;
		var attempt = 49000;
		while (p == 0 && attempt < 49200) {
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
			throw "LocalServer: could not bind a loopback port";
		}
		return p;
	}

	/**
	 * Accept the first client on a background thread, stream the chunks, then
	 * close.
	 */
	public function start():Void {
		Thread.create(function() {
			try {
				var client = _listener.accept();
				for (chunk in _chunks) {
					if (!_running) {
						break;
					}
					client.output.writeBytes(chunk, 0, chunk.length);
					client.output.flush();
					if (_delayMs > 0) {
						Sys.sleep(_delayMs / 1000);
					}
				}
				// Let the client drain before closing.
				Sys.sleep(0.05);
				try {
					client.close();
				} catch (e:Dynamic) {}
			} catch (e:Dynamic) {
				// Test will time out / assert; nothing to do here.
			}
		});
	}

	public function stop():Void {
		_running = false;
		if (_listener != null) {
			try {
				_listener.close();
			} catch (e:Dynamic) {}
			_listener = null;
		}
	}
}
