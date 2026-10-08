package hxSockets;

/**
 * Certificate validation status (OpenFL-style string values).
 *
 * Produced by SecureSocket today: trusted, unknown, invalid, expired, notYetValid.
 * Declared for API parity but not assigned yet: invalidChain, principalMismatch,
 * revoked, untrustedSigners.
 *
 * After close(), status is reset to unknown, so do not rely on status alone after
 * failures; prefer onConnect as the success signal.
 */
enum abstract CertificateStatus(String) from String to String {
	/** Peer notAfter is before now (extra check after handshake). */
	var EXPIRED = "expired";
	/** Connect, handshake, or certificate failure (may be cleared to unknown on close). */
	var INVALID = "invalid";
	/** Not assigned yet (parity placeholder). */
	var INVALID_CHAIN = "invalidChain";
	/** Peer notBefore is after now (extra check after handshake). */
	var NOT_YET_VALID = "notYetValid";
	/** Not assigned yet (parity placeholder). */
	var PRINCIPAL_MISMATCH = "principalMismatch";
	/** Not assigned yet (parity placeholder). */
	var REVOKED = "revoked";
	/** Handshake and validity window accepted. */
	var TRUSTED = "trusted";
	/** Initial value, and value after close(). */
	var UNKNOWN = "unknown";
	/** Not assigned yet (parity placeholder). */
	var UNTRUSTED_SIGNERS = "untrustedSigners";
}

/**
 * X.500 Distinguished Name
 */
class X500DistinguishedName {
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var commonName(default, null):String;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var countryName(default, null):String;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var localityName(default, null):String;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var organizationalUnitName(default, null):String;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var organizationName(default, null):String;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var stateOrProvinceName(default, null):String;
	
	public function new() {}
	
	public function toString():String {
		var parts = [];
		if (commonName != null) parts.push('CN=$commonName');
		if (countryName != null) parts.push('C=$countryName');
		if (localityName != null) parts.push('L=$localityName');
		if (organizationalUnitName != null) parts.push('OU=$organizationalUnitName');
		if (organizationName != null) parts.push('O=$organizationName');
		if (stateOrProvinceName != null) parts.push('S=$stateOrProvinceName');
		return "/" + parts.join("/");
	}
}

/**
 * X.509 Certificate
 */
class X509Certificate {
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var subject(default, null):X500DistinguishedName;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var issuer(default, null):X500DistinguishedName;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var validNotBefore(default, null):Date;
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	public var validNotAfter(default, null):Date;
	
	public function new() {}
	
	public function toString():String {
		return 'X509Certificate[subject=${subject}, issuer=${issuer}, valid=${validNotBefore} to ${validNotAfter}]';
	}
}