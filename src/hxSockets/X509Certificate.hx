package hxSockets;

/**
 * Certificate validation status
 */
enum abstract CertificateStatus(String) from String to String {
	var EXPIRED = "expired";
	var INVALID = "invalid";
	var INVALID_CHAIN = "invalidChain";
	var NOT_YET_VALID = "notYetValid";
	var PRINCIPAL_MISMATCH = "principalMismatch";
	var REVOKED = "revoked";
	var TRUSTED = "trusted";
	var UNKNOWN = "unknown";
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