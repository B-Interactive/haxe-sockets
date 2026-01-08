package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import hxSockets.X509Certificate;

/**
 * Tests for Certificate-related classes
 */
class CertificateTests extends Test {
	
	// X500DistinguishedName Tests
	
	function testX500DistinguishedName_EmptyInstance() {
		var dn = new X500DistinguishedName();
		Assert.isNull(dn.commonName);
		Assert.isNull(dn.countryName);
		Assert.isNull(dn.localityName);
		Assert.isNull(dn.organizationName);
		Assert.isNull(dn.organizationalUnitName);
		Assert.isNull(dn.stateOrProvinceName);
	}

	function testX500DistinguishedName_ToString_Empty() {
		var dn = new X500DistinguishedName();
		Assert.equals("/", dn.toString());
	}

	function testX500DistinguishedName_ToString_WithCommonName() {
		var dn = new X500DistinguishedName();
		dn.commonName = "example.com";
		Assert.equals("/CN=example.com", dn.toString());
	}

	function testX500DistinguishedName_ToString_Complete() {
		var dn = new X500DistinguishedName();
		dn.commonName = "example.com";
		dn.countryName = "US";
		dn.localityName = "San Francisco";
		dn.organizationName = "Example Inc";
		dn.organizationalUnitName = "IT";
		dn.stateOrProvinceName = "California";

		var str = dn.toString();
		Assert.isTrue(str.indexOf("CN=example.com") > -1);
		Assert.isTrue(str.indexOf("C=US") > -1);
		Assert.isTrue(str.indexOf("L=San Francisco") > -1);
		Assert.isTrue(str.indexOf("O=Example Inc") > -1);
		Assert.isTrue(str.indexOf("OU=IT") > -1);
		Assert.isTrue(str.indexOf("S=California") > -1);
	}

	function testX500DistinguishedName_ToString_Partial() {
		var dn = new X500DistinguishedName();
		dn.commonName = "test.com";
		dn.organizationName = "Test Org";

		var str = dn.toString();
		Assert.isTrue(str.indexOf("CN=test.com") > -1);
		Assert.isTrue(str.indexOf("O=Test Org") > -1);
		Assert.isFalse(str.indexOf("C=") > -1);
		Assert.isFalse(str.indexOf("L=") > -1);
	}

	// X509Certificate Tests

	function testX509Certificate_EmptyInstance() {
		var cert = new X509Certificate();
		Assert.isNull(cert.subject);
		Assert.isNull(cert.issuer);
		Assert.isNull(cert.validNotBefore);
		Assert.isNull(cert.validNotAfter);
	}

	function testX509Certificate_ToString_Empty() {
		var cert = new X509Certificate();
		var str = cert.toString();
		Assert.isTrue(str.indexOf("X509Certificate") > -1);
		Assert.isTrue(str.indexOf("null") > -1);
	}

	function testX509Certificate_ToString_WithData() {
		var cert = new X509Certificate();

		var subject = new X500DistinguishedName();
		subject.commonName = "example.com";
		cert.subject = subject;

		var issuer = new X500DistinguishedName();
		issuer.commonName = "CA Root";
		cert.issuer = issuer;

		cert.validNotBefore = Date.now();
		cert.validNotAfter = Date.now();

		var str = cert.toString();
		Assert.isTrue(str.indexOf("X509Certificate") > -1);
		Assert.isTrue(str.indexOf("example.com") > -1);
		Assert.isTrue(str.indexOf("CA Root") > -1);
	}

	// CertificateStatus Tests

	function testCertificateStatus_AllValues() {
		var statuses = [
			CertificateStatus.EXPIRED,
			CertificateStatus.INVALID,
			CertificateStatus.INVALID_CHAIN,
			CertificateStatus.NOT_YET_VALID,
			CertificateStatus.PRINCIPAL_MISMATCH,
			CertificateStatus.REVOKED,
			CertificateStatus.TRUSTED,
			CertificateStatus.UNKNOWN,
			CertificateStatus.UNTRUSTED_SIGNERS
		];

		Assert.equals(9, statuses.length);
	}

	function testCertificateStatus_StringValues() {
		Assert.equals("expired", CertificateStatus.EXPIRED);
		Assert.equals("invalid", CertificateStatus.INVALID);
		Assert.equals("invalidChain", CertificateStatus.INVALID_CHAIN);
		Assert.equals("notYetValid", CertificateStatus.NOT_YET_VALID);
		Assert.equals("principalMismatch", CertificateStatus.PRINCIPAL_MISMATCH);
		Assert.equals("revoked", CertificateStatus.REVOKED);
		Assert.equals("trusted", CertificateStatus.TRUSTED);
		Assert.equals("unknown", CertificateStatus.UNKNOWN);
		Assert.equals("untrustedSigners", CertificateStatus.UNTRUSTED_SIGNERS);
	}

	function testCertificateStatus_Comparison() {
		var status1:CertificateStatus = TRUSTED;
		var status2:CertificateStatus = TRUSTED;
		var status3:CertificateStatus = INVALID;

		Assert.equals(status1, status2);
		Assert.notEquals(status1, status3);
	}

	function testCertificateStatus_FromString() {
		var status:CertificateStatus = "trusted";
		Assert.equals(CertificateStatus.TRUSTED, status);
	}

	function testCertificateStatus_ToString() {
		var status:CertificateStatus = TRUSTED;
		var str:String = status;
		Assert.equals("trusted", str);
	}
}