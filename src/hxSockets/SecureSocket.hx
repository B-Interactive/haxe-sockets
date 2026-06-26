package hxSockets;

import hxSockets.X509Certificate;
import haxe.io.Error;
import sys.net.Host;
import sys.ssl.Certificate;
import sys.ssl.Key;

/**
 * Secure TLS/SSL socket. Extends Socket with encryption and certificate
 * validation. Supports server-authenticated TLS (default) and mutual TLS
 * via setClientCertificate() / setCA().
 */
class SecureSocket extends Socket {
	public var serverCertificate(get, never):X509Certificate;
	public var serverCertificateStatus(get, never):CertificateStatus;

	var _serverCertificate:X509Certificate;
	var _certificateStatus:CertificateStatus = UNKNOWN;
	var _peerCert:Certificate;
	var _handshakeComplete:Bool = false;
	var _handshakeStarted:Bool = false;

	// Optional mTLS / pinning material; null unless configured.
	var _clientCert:Certificate;
	var _clientKey:Key;
	var _serverCa:Certificate;

	var secureSocket:sys.ssl.Socket;

	/**
	 * Create a secure socket. See Socket.new for the manualPoll argument.
	 */
	public function new(manualPoll:Bool = false) {
		super(manualPoll);
	}

	/**
	 * Set a PEM client certificate and key to present during the handshake
	 * (mutual TLS), optionally pinning the server CA too. Applied on the next
	 * connect().
	 */
	public function setClientCertificate(certPemPath:String, keyPemPath:String, ?caPemPath:String):Void {
		_clientCert = Certificate.loadFile(certPemPath);
		_clientKey = Key.loadFile(keyPemPath);
		if (caPemPath != null) {
			_serverCa = Certificate.loadFile(caPemPath);
		}
	}

	/**
	 * Pin a server CA certificate (PEM file) to validate the server against.
	 * Applied on the next connect().
	 */
	public function setCA(caPemPath:String):Void {
		_serverCa = Certificate.loadFile(caPemPath);
	}

	/**
	 * Connect to a host and port using TLS/SSL.
	 */
	override public function connect(host:String, port:Int):Void {
		if (_socket != null) {
			close();
		}

		if (port < 0 || port > 65535) {
			_emitError(Other, "Invalid port number: " + port);
			return;
		}

		var h:Host = null;
		try {
			h = new Host(host);
		} catch (e:Dynamic) {
			_emitError(Other, "Invalid host: " + host);
			return;
		}

		_host = host;
		_port = port;
		_timestamp = Sys.time();
		_certificateStatus = UNKNOWN;
		_handshakeComplete = false;
		_handshakeStarted = false;
		_peerCert = null;
		_serverCertificate = null;
		_receiveBuffer.clear();

		try {
			_socket = new sys.ssl.Socket();
			secureSocket = getSecureSocket();
			secureSocket.setBlocking(false);
			secureSocket.setHostname(host);
			secureSocket.verifyCert = true;
			// Apply pinning + client identity before the handshake.
			if (_serverCa != null) {
				secureSocket.setCA(_serverCa);
			}
			if (_clientCert != null) {
				secureSocket.setCertificate(_clientCert, _clientKey);
			}
			secureSocket.connect(h, port);
			secureSocket.setFastSend(true);
		} catch (e:Dynamic) {
			_certificateStatus = INVALID;
			_emitError(Other, "Connection failed");
			return;
		}

		_startPolling();
	}

	/**
	 * Close the secure socket. Idempotent; resets TLS handshake state.
	 */
	override public function close():Void {
		super.close();
		secureSocket = null;
		_handshakeComplete = false;
		_handshakeStarted = false;
		_certificateStatus = UNKNOWN;
		_peerCert = null;
		_serverCertificate = null;
	}

	override function _poll():Void {
		if (_socket == null) {
			return;
		}

		// If already connected and handshake complete, just do normal polling
		if (_connected && _handshakeComplete) {
			super._poll();
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
			close();
			_emitError(Timeout, "Connection timeout");
			return;
		}

		// Handle TLS handshake
		if (doConnect || _handshakeStarted) {
			if (!_handshakeStarted) {
				_handshakeStarted = true;
			}

			var handshakeBlocked = false;

			try {
				secureSocket.handshake();
				// If we get here without exception, handshake succeeded
			} catch (e:Error) {
				switch (e) {
					case Error.Blocked | Error.Custom(Error.Blocked):
						handshakeBlocked = true;
					default:
						_certificateStatus = INVALID;
						close();
						_emitError(_classifyHandshakeError(Std.string(e)), "TLS handshake failed");
						return;
				}
			} catch (e:Dynamic) {
				_certificateStatus = INVALID;
				close();
				_emitError(_classifyHandshakeError(Std.string(e)), "TLS handshake failed");
				return;
			}

			if (handshakeBlocked) {
				// Handshake still in progress, try again next frame
				return;
			}

			// Handshake complete, validate certificate.
			// handshake() is the authoritative check (trust chain, hostname)
			try {
				_peerCert = secureSocket.peerCertificate();
				if (_peerCert == null) {
					_certificateStatus = INVALID;
					close();
					_emitError(CertificateRejected, "Invalid server certificate");
					return;
				}

				// Build the wrapper so validity dates are available for the checks below.
				_serverCertificate = _createCertificateObject(_peerCert);

				// The platform TLS handshake is the primary check, this is an extra check.
				var now = Date.now().getTime();
				if (_serverCertificate.validNotBefore != null && now < _serverCertificate.validNotBefore.getTime()) {
					_certificateStatus = NOT_YET_VALID;
					close();
					_emitError(CertificateRejected, "Server certificate not yet valid");
					return;
				}
				if (_serverCertificate.validNotAfter != null && now > _serverCertificate.validNotAfter.getTime()) {
					_certificateStatus = EXPIRED;
					close();
					_emitError(CertificateRejected, "Server certificate expired");
					return;
				}

				// All checks passed: the handshake verified trust and the validity window is good.
				_certificateStatus = TRUSTED;
				_handshakeComplete = true;
				_connected = true;

				if (onConnect != null) {
					onConnect();
				}
			} catch (e:Dynamic) {
				_certificateStatus = INVALID;
				close();
				_emitError(CertificateRejected, "Certificate validation failed");
				return;
			}
		}
	}

	/**
	 * Classify a handshake failure string as a certificate rejection or a
	 * generic handshake failure.
	 *
	 * Best-effort guess based on the error text, so results can vary by platform.
	 * It only picks the error kind; either way the connection is still closed.
	 */
	function _classifyHandshakeError(message:String):SocketErrorKind {
		var m = message.toLowerCase();
		var certIndicators = [
			"certificate", "cert", "verify", "verification",
			"x509", "ca cert", "unknown ca", "self signed",
			"self-signed", "trust", "chain", "expired"
		];
		for (token in certIndicators) {
			if (m.indexOf(token) > -1) {
				return CertificateRejected;
			}
		}
		return TlsHandshakeFailed;
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
	function get_serverCertificate():X509Certificate {
		return _serverCertificate;
	}

	function get_serverCertificateStatus():CertificateStatus {
		return _certificateStatus;
	}
}
