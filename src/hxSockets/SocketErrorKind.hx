package hxSockets;

/**
 * Classification of a socket failure, so callers can react without parsing
 * the error string passed to onError. TLS cert-vs-handshake kinds are best-effort
 * (platform error text) and should be treated as advisory.
 */
enum abstract SocketErrorKind(String) from String to String {
	/** The peer closed the connection, or the link was lost. */
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
