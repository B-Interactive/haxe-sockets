package hxSockets.tests;

import haxe.io.Bytes;
import sys.net.Host;
import sys.ssl.Certificate;
import sys.ssl.Key;
import sys.ssl.Socket as SslSocket;
import sys.thread.Thread;

/**
 * A minimal local TLS server that requires a client certificate (mutual TLS),
 * built on sys.ssl.Socket. Used by the mTLS tests. On a successful handshake it
 * writes a known payload and closes; an untrusted client fails the handshake.
 * Runs on its own thread.
 */
class MtlsServer {
	public var port(default, null):Int;
	public var lastClientAccepted(default, null):Bool = false;

	var _listener:SslSocket;
	var _payload:Bytes;
	var _running:Bool = true;

	public function new(caCertPath:String, serverCertPath:String, serverKeyPath:String, payload:Bytes) {
		_payload = payload;

		var listener = new SslSocket();
		listener.setCertificate(Certificate.loadFile(serverCertPath), Key.loadFile(serverKeyPath));
		// Require a client certificate signed by this CA (mTLS).
		listener.setCA(Certificate.loadFile(caCertPath));
		listener.verifyCert = true;

		port = _bind(listener);
		_listener = listener;
	}

	function _bind(listener:SslSocket):Int {
		var p = 0;
		var attempt = 49200;
		while (p == 0 && attempt < 49400) {
			try {
				listener.bind(new Host("127.0.0.1"), attempt);
				listener.listen(1);
				p = attempt;
			} catch (e:Dynamic) {
				attempt++;
			}
		}
		if (p == 0) {
			throw "MtlsServer: could not bind a loopback port";
		}
		return p;
	}

	/**
	 * Accept one client (performing the mTLS handshake), serve the payload, then
	 * close. A handshake failure leaves lastClientAccepted false.
	 */
	public function start():Void {
		Thread.create(function() {
			try {
				var client:SslSocket = cast _listener.accept();
				// accept() performs the handshake; reaching here means success.
				lastClientAccepted = true;
				try {
					client.output.writeBytes(_payload, 0, _payload.length);
					client.output.flush();
				} catch (e:Dynamic) {}
				Sys.sleep(0.05);
				try {
					client.close();
				} catch (e:Dynamic) {}
			} catch (e:Dynamic) {
				// Handshake failed (expected in the negative case).
				lastClientAccepted = false;
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
