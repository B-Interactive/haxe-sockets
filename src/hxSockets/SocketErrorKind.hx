package hxSockets;

/**
 * Classification of a socket failure, so callers can react without parsing
 * the error string passed to onError. TLS cert-vs-handshake kinds are best-effort
 * (platform error text) and should be treated as advisory.
 */
enum abstract SocketErrorKind(String) from String to String {
	/** The link was lost during I/O (a read or write fault). A clean peer
	 *  close is not a fault and does not report this kind. */
	var ConnectionLost = "connectionLost";

	/** The connect attempt timed out. */
	var Timeout = "timeout";

	/** The TLS handshake failed (not classified as a certificate rejection). */
	var TlsHandshakeFailed = "tlsHandshakeFailed";

	/** A certificate was rejected, or error text suggested a cert/verify failure. */
	var CertificateRejected = "certificateRejected";

	/** Any other failure. */
	var Other = "other";
}
