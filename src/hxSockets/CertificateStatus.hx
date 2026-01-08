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
	public var commonName(default, null):String;
	public var countryName(default, null):String;
	public var localityName(default, null):String;
	public var organizationalUnitName(default, null):String;
	public var organizationName(default, null):String;
	public var stateOrProvinceName(default, null):String;
	
	public function new() {}
	
	/**
	 * Internal setters (used by SecureSocket and tests)
	 */
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	function setCommonName(value:String):Void {
		commonName = value;
	}
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	function setCountryName(value:String):Void {
		countryName = value;
	}
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	function setLocalityName(value:String):Void {
		localityName = value;
	}
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	function setOrganizationName(value:String):Void {
		organizationName = value;
	}
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	function setOrganizationalUnitName(value:String):Void {
		organizationalUnitName = value;
	}
	
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	function setStateOrProvinceName(value:String):Void {
		stateOrProvinceName = value;
	}
	
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
	public var subject(default, null):X500DistinguishedName;
	public var issuer(default, null):X500DistinguishedName;
	public var validNotBefore(default, null):Date;
	public var validNotAfter(default, null):Date;
	
	// Internal setters (accessed by SecureSocket)
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	var _subject:X500DistinguishedName;
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	var _issuer:X500DistinguishedName;
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	var _validNotBefore:Date;
	@:allow(hxSockets.SecureSocket)
	@:allow(hxSockets.tests)
	var _validNotAfter:Date;
	
	public function new() {}
	
	public function toString():String {
		return 'X509Certificate[subject=${subject}, issuer=${issuer}, valid=${validNotBefore} to ${validNotAfter}]';
	}
}