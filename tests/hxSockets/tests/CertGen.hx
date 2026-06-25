package hxSockets.tests;

import sys.FileSystem;
import sys.io.File;

/**
 * Generates throwaway TLS test material (CA, server and client cert/key) into a
 * temp directory using openssl. Used by the mTLS tests. Returns null when
 * openssl is unavailable or any step fails, so the tests can SKIP.
 */
class CertGen {
	public var dir(default, null):String;
	public var caCert(default, null):String;
	public var serverCert(default, null):String;
	public var serverKey(default, null):String;
	public var clientCert(default, null):String;
	public var clientKey(default, null):String;

	function new(dir:String) {
		this.dir = dir;
		caCert = haxe.io.Path.join([dir, "ca.crt"]);
		serverCert = haxe.io.Path.join([dir, "server.crt"]);
		serverKey = haxe.io.Path.join([dir, "server.key"]);
		clientCert = haxe.io.Path.join([dir, "client.crt"]);
		clientKey = haxe.io.Path.join([dir, "client.key"]);
	}

	/**
	 * Return true if openssl is runnable.
	 */
	public static function hasOpenssl():Bool {
		try {
			return Sys.command("openssl", ["version"]) == 0;
		} catch (e:Dynamic) {
			return false;
		}
	}

	/**
	 * Generate all material, or return null on any failure.
	 */
	public static function generate():CertGen {
		if (!hasOpenssl()) {
			return null;
		}

		var base = Sys.getCwd();
		var dir = haxe.io.Path.join([base, "tests_tmp_certs_" + Std.int(Sys.time() * 1000)]);
		try {
			FileSystem.createDirectory(dir);
		} catch (e:Dynamic) {
			return null;
		}

		var cg = new CertGen(dir);

		// SAN extfile so the server cert validates for 127.0.0.1 / localhost.
		var sanPath = haxe.io.Path.join([dir, "san.cnf"]);
		try {
			File.saveContent(sanPath, "subjectAltName=IP:127.0.0.1,DNS:localhost\n");
		} catch (e:Dynamic) {
			return null;
		}

		var caKey = haxe.io.Path.join([dir, "ca.key"]);
		var serverCsr = haxe.io.Path.join([dir, "server.csr"]);
		var clientCsr = haxe.io.Path.join([dir, "client.csr"]);

		// Each step must succeed (exit 0).
		var steps:Array<Array<String>> = [
			// Private CA (self-signed).
			["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", caKey, "-out", cg.caCert, "-days", "1", "-subj", "/CN=hxSockets Test CA"],
			// Server key + CSR.
			["req", "-newkey", "rsa:2048", "-nodes", "-keyout", cg.serverKey, "-out", serverCsr, "-subj", "/CN=localhost"],
			// Sign server cert with CA + SAN.
			[
				"x509", "-req", "-in", serverCsr, "-CA", cg.caCert, "-CAkey", caKey, "-CAcreateserial", "-out", cg.serverCert, "-days", "1", "-extfile",
				sanPath
			],
			// Client key + CSR.
			["req", "-newkey", "rsa:2048", "-nodes", "-keyout", cg.clientKey, "-out", clientCsr, "-subj", "/CN=hxSockets Test Client"],
			// Sign client cert with CA.
			["x509", "-req", "-in", clientCsr, "-CA", cg.caCert, "-CAkey", caKey, "-CAcreateserial", "-out", cg.clientCert, "-days", "1"]
		];

		for (args in steps) {
			var code = -1;
			try {
				code = Sys.command("openssl", args);
			} catch (e:Dynamic) {
				code = -1;
			}
			if (code != 0) {
				return null;
			}
		}

		// Sanity: all expected files exist.
		if (!FileSystem.exists(cg.caCert)
			|| !FileSystem.exists(cg.serverCert)
			|| !FileSystem.exists(cg.serverKey)
			|| !FileSystem.exists(cg.clientCert)
			|| !FileSystem.exists(cg.clientKey)) {
			return null;
		}

		return cg;
	}

	/**
	 * Delete the temp directory and its contents.
	 */
	public function cleanup():Void {
		_deleteRecursive(dir);
	}

	static function _deleteRecursive(path:String):Void {
		try {
			if (!FileSystem.exists(path)) {
				return;
			}
			if (FileSystem.isDirectory(path)) {
				for (entry in FileSystem.readDirectory(path)) {
					_deleteRecursive(haxe.io.Path.join([path, entry]));
				}
				FileSystem.deleteDirectory(path);
			} else {
				FileSystem.deleteFile(path);
			}
		} catch (e:Dynamic) {
			// Best-effort cleanup of throwaway material.
		}
	}
}
