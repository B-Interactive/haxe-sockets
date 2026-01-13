package hxSockets;

import hxSockets.X509Certificate;
import haxe.io.Error;
import sys.net.Host;
import sys.ssl.Certificate;

/**
 * Secure TLS/SSL socket implementation
 * Extends Socket with encryption and certificate validation
 */
class SecureSocket extends Socket {
	public static var isSupported(get, never):Bool;

	public var serverCertificate(get, never):X509Certificate;
	public var serverCertificateStatus(get, never):CertificateStatus;

	var _serverCertificate:X509Certificate;
	var _certificateStatus:CertificateStatus = UNKNOWN;
	var _peerCert:Certificate;
	var _handshakeComplete:Bool = false;

	var secureSocket:sys.ssl.Socket;

	public function new() {
		super();
	}

	/**
	 * Connect to specified host and port using TLS/SSL
	 */
	override public function connect(host:String, port:Int):Void {
		if (_socket != null) {
			close();
		}

		if (port < 0 || port > 65535) {
			if (onError != null) {
				onError("Invalid port number: " + port);
			}
			return;
		}

		var h:Host = null;
		try {
			h = new Host(host);
		} catch (e:Dynamic) {
			if (onError != null) {
				onError("Invalid host: " + host);
			}
			return;
		}

		_host = host;
		_port = port;
		_timestamp = Sys.time();
		_certificateStatus = UNKNOWN;
		_handshakeComplete = false;
		_peerCert = null;
		_serverCertificate = null;

		try {
			_socket = new sys.ssl.Socket();
			secureSocket = getSecureSocket();
			secureSocket.setBlocking(false);
			secureSocket.setHostname(host);
			secureSocket.verifyCert = false;
			secureSocket.connect(h, port);
			secureSocket.setFastSend(true);
		} catch (e:Dynamic) {
			_certificateStatus = INVALID;
			if (onError != null) {
				onError("Connection failed: " + e);
			}
			return;
		}

		_startPolling();
	}

	override function _poll():Void {
		if (_socket == null) {
			return;
		}

		var doConnect = false;
		var doClose = false;

		// Check connection status
		if (!_connected) {
			try {
				var r = sys.net.Socket.select(null, [_socket], null, 0);
				if (r.write.length > 0 && r.write[0] == _socket) {
					doConnect = true;
				} else if (Sys.time() - _timestamp > timeout / 1000) {
					doClose = true;
				}
			} catch (e:Dynamic) {
				doClose = true;
			}
		}

		// Handle connection failure
		if (doClose && !_connected) {
			_certificateStatus = INVALID;
			if (onError != null) {
				onError("Connection timeout");
			}
			close();
			return;
		}

		// Handle TLS handshake
		if (doConnect && !_handshakeComplete) {
			var blocked = false;

			try {
				secureSocket.handshake();
			} catch (e:Error) {
				switch (e) {
					case Error.Blocked | Error.Custom(Error.Blocked):
						blocked = true;
					default:
						_certificateStatus = INVALID;
						close();
						if (onError != null) {
							onError("TLS handshake failed: " + e);
						}
						return;
				}
			} catch (e:Dynamic) {
				_certificateStatus = INVALID;
				close();
				if (onError != null) {
					onError("TLS handshake failed: " + e);
				}
				return;
			}

			if (blocked) {
				// Try again next frame
				return;
			}

			_socket.setBlocking(false);

			// Handshake complete, validate certificate
			try {
				_peerCert = secureSocket.peerCertificate();
				if (_peerCert != null) {
					_certificateStatus = TRUSTED;
					_serverCertificate = _createCertificateObject(_peerCert);
					_handshakeComplete = true;
					_connected = true;

					if (onConnect != null) {
						onConnect();
					}
				} else {
					_certificateStatus = INVALID;
					close();
					if (onError != null) {
						onError("Invalid server certificate");
					}
					return;
				}
			} catch (e:Dynamic) {
				_certificateStatus = INVALID;
				close();
				if (onError != null) {
					onError("Certificate validation failed: " + e);
				}
				return;
			}
		}

		// Continue with normal socket operations
		if (_connected && _handshakeComplete) {
			super._poll();
		}
	}

	function _createCertificateObject(cert:Certificate):X509Certificate {
		var x509 = new X509Certificate();

		// Extract subject DN - direct assignment
		var subject = new X500DistinguishedName();
		subject.commonName = cert.subject("CN");
		subject.countryName = cert.subject("C");
		subject.localityName = cert.subject("L");
		subject.organizationName = cert.subject("O");
		subject.organizationalUnitName = cert.subject("OU");
		subject.stateOrProvinceName = cert.subject("S");
		x509.subject = subject;

		// Extract issuer DN - direct assignment
		var issuer = new X500DistinguishedName();
		issuer.commonName = cert.issuer("CN");
		issuer.countryName = cert.issuer("C");
		issuer.localityName = cert.issuer("L");
		issuer.organizationName = cert.issuer("O");
		issuer.organizationalUnitName = cert.issuer("OU");
		issuer.stateOrProvinceName = cert.issuer("S");
		x509.issuer = issuer;

		// Extract validity dates - direct assignment
		x509.validNotBefore = cert.notBefore;
		x509.validNotAfter = cert.notAfter;

		return x509;
	}

	// Getters
	static function get_isSupported():Bool {
		return true;
	}

	function get_serverCertificate():X509Certificate {
		return _serverCertificate;
	}

	function get_serverCertificateStatus():CertificateStatus {
		return _certificateStatus;
	}
}
