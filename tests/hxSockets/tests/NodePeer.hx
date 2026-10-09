package hxSockets.tests;

import haxe.Exception;
import sys.FileSystem;
import sys.io.Process;
import sys.thread.Thread;
import utest.Assert;
import utest.Async;

/**
 * Handle for a running peer process: the reported listen address and a stop
 * callback that kills it.
 */
typedef NodePeerHandle = {
	var host:String;
	var port:Int;
	var stop:Void->Void;
}

/**
 * Driver for the loopback Node.js peer in `tests/peer-node/peer.js`. Spawns
 * `node` with a scripted mode, waits for the one-line READY handshake on
 * stdout, and kills the process again on stop. Node is a soft dependency:
 * every case SKIPs cleanly when the binary is missing. Verified runtime is
 * Node.js 26.x; other versions are allowed with a note, never hard-failed.
 */
class NodePeer {
	/** Seconds to wait for the READY line before giving up on a spawn. */
	static inline final READY_TIMEOUT_SECONDS:Float = 5.0;

	static var _available:Null<Bool>;

	/**
	 * True when `node` is runnable. Probed once per run and kept quiet;
	 * `-D skip_node_peer` forces the skip path. A non-26.x major is traced
	 * as a note only.
	 */
	public static function isAvailable():Bool {
		#if skip_node_peer
		return false;
		#end
		if (_available == null) {
			_available = false;
			try {
				var p = new Process("node", ["-v"]);
				var version = p.stdout.readLine();
				p.exitCode();
				p.close();
				if (version != null && version.length > 1) {
					_available = true;
					var major = Std.parseInt(version.substr(1));
					if (major != 26) {
						trace('NodePeer: node ${version} found (verified runtime is 26.x)');
					}
				}
			} catch (e:Dynamic) {
				// No node on PATH: the probe simply reports unavailable.
			}
		}
		return _available;
	}

	/**
	 * Skip a Node peer test when node is unavailable: traces the reason,
	 * passes cleanly (warnings would turn an offline CI run red), resolves
	 * `async`, and returns `true` so the caller can `return`.
	 */
	public static function skipIfUnavailable(async:Async):Bool {
		if (isAvailable()) {
			return false;
		}
		#if skip_node_peer
		trace("SKIPPED: node peer tests disabled (-D skip_node_peer)");
		#else
		trace("SKIPPED: node binary unavailable - skipping Node peer test");
		#end
		Assert.pass();
		async.done();
		return true;
	}

	/**
	 * Start the peer in the given mode with optional extra CLI options
	 * (e.g. `["--chunk-count", "3"]`) and wait for its READY line.
	 * Throws when the spawn, the READY handshake or its parsing fails;
	 * callers must invoke `stop()` in a finally block.
	 *
	 * Assumes the test binary runs from the repository root (as the project
	 * hxml `-cmd` lines do), so the peer script path is resolved from CWD.
	 */
	public static function start(mode:String, ?extraArgs:Array<String>):NodePeerHandle {
		var args = [peerScript(), "--mode", mode];
		if (extraArgs != null) {
			args = args.concat(extraArgs);
		}

		var proc = null;
		try {
			proc = new Process("node", args);
		} catch (e:Dynamic) {
			throw new Exception('NodePeer: failed to spawn node: ${e}');
		}

		// Read the READY line on a helper thread so a peer that never prints
		// it cannot block the runner.
		var line:Null<String> = null;
		var failed = false;
		Thread.create(function() {
			try {
				line = proc.stdout.readLine();
			} catch (e:Dynamic) {
				failed = true;
			}
		});

		var deadline = Sys.time() + READY_TIMEOUT_SECONDS;
		while (line == null && !failed && Sys.time() < deadline) {
			Sys.sleep(0.01);
		}

		if (failed || line == null) {
			// Kill first so any still-open pipe reaches EOF, then collect the
			// peer's stderr for the failure message.
			stopProcess(proc);
			var detail = if (failed) {
				var err = "";
				try {
					err = StringTools.trim(proc.stderr.readAll().toString());
				} catch (e:Dynamic) {}
				"peer exited before READY" + (err == "" ? "" : ": " + err);
			} else {
				"no READY line within " + READY_TIMEOUT_SECONDS + "s";
			}
			throw new Exception('NodePeer: ${detail}');
		}

		var parts = StringTools.trim(line).split(" ");
		if (parts.length != 3 || parts[0] != "READY") {
			stopProcess(proc);
			throw new Exception('NodePeer: malformed READY line: "${line}"');
		}
		var host = parts[1];
		var port = Std.parseInt(parts[2]);
		if (port == null) {
			stopProcess(proc);
			throw new Exception('NodePeer: bad port in READY line: "${line}"');
		}

		return {
			host: host,
			port: port,
			stop: function() {
				stopProcess(proc);
			}
		};
	}

	static function peerScript():String {
		var script = haxe.io.Path.join([Sys.getCwd(), "tests", "peer-node", "peer.js"]);
		if (!FileSystem.exists(script)) {
			throw new Exception('NodePeer: peer script not found at ${script} (tests must run from the repository root)');
		}
		return script;
	}

	static function stopProcess(proc:Process):Void {
		try {
			proc.kill();
		} catch (e:Dynamic) {}
		try {
			proc.close();
		} catch (e:Dynamic) {}
	}
}
