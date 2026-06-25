package hxSockets;

/**
 * Classification of a socket failure, so callers can react without parsing
 * the error string passed to onError.
 */
enum abstract SocketErrorKind(String) from String to String {
	/** The peer closed the connection, or the link was lost. */
	var ConnectionLost = "connectionLost";

	/** The connect attempt timed out. */
	var Timeout = "timeout";

	/** The TLS handshake failed (not a certificate rejection). */
	var TlsHandshakeFailed = "tlsHandshakeFailed";

	/** A certificate was rejected during the handshake. */
	var CertificateRejected = "certificateRejected";

	/** Any other failure. */
	var Other = "other";
}
