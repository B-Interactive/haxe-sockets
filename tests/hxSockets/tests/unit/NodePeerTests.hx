package hxSockets.tests.unit;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import hxSockets.Socket;
import hxSockets.tests.NodePeer;
import hxSockets.tests.NodePeer.NodePeerHandle;
import hxSockets.tests.TestHelpers;
import utest.Test;
import utest.Assert;
import utest.Async;

/**
 * Cross-runtime interop tests: hxSockets.Socket against a local Node.js TCP
 * peer (`tests/peer-node/peer.js`). Real loopback sockets, no mocks. The whole
 * class SKIPs cleanly when the `node` binary is missing, so the offline CI
 * path stays green without Node. Sockets use manual poll for determinism.
 *
 * The class-level timeout exceeds the library default `Socket.timeout` so
 * utest never aborts before the socket could.
 */
@:timeout(TestHelpers.SOCKET_TEST_TIMEOUT)
class NodePeerTests extends Test {
	var peers:Array<NodePeerHandle> = [];

	function teardown():Void {
		// Always stop spawned peers, even when a test bailed out early.
		for (peer in peers) {
			peer.stop();
		}
		peers = [];
	}

	function startPeer(mode:String, ?extraArgs:Array<String>):NodePeerHandle {
		var peer = NodePeer.start(mode, extraArgs);
		peers.push(peer);
		return peer;
	}

	// Pump poll() until the condition holds or the time budget expires.
	function pump(socket:Socket, condition:Void->Bool, budgetSeconds:Float):Bool {
		var start = Sys.time();
		while (Sys.time() - start < budgetSeconds) {
			socket.poll();
			if (condition()) {
				return true;
			}
			Sys.sleep(0.005);
		}
		return false;
	}

	/**
	 * Binary echo round-trip against the Node peer, driven by manual poll:
	 * the socket makes no progress until poll() is pumped, then every byte
	 * written comes back unchanged (Node may coalesce the echo).
	 */
	function testEchoBinaryRoundTripWithManualPoll(async:Async) {
		if (NodePeer.skipIfUnavailable(async)) {
			return;
		}

		var peer = startPeer("echo");
		var socket = new Socket(true); // manual poll
		var connected = false;
		socket.onConnect = function() {
			connected = true;
		};

		socket.connect(peer.host, peer.port);

		// Manual-poll check: nothing advances unless poll() is called.
		Sys.sleep(0.15);
		Assert.isFalse(connected, "manual-poll socket must not connect without poll()");

		Assert.isTrue(pump(socket, function() return connected, 5), "should connect against the Node peer");

		var payload = TestHelpers.createTestBytes(512);
		socket.writeBytes(payload);
		socket.flush();

		var received = new BytesBuffer();
		var start = Sys.time();
		while (received.length < payload.length && Sys.time() - start < 5) {
			socket.poll();
			if (socket.bytesAvailable > 0) {
				var chunk = socket.readAllBytes();
				received.addBytes(chunk, 0, chunk.length);
			}
			Sys.sleep(0.005);
		}

		Assert.equals(payload.length, received.length, "the full echo should arrive under manual polling");
		Assert.isTrue(TestHelpers.bytesEqual(payload, received.getBytes()), "echoed bytes must match the payload exactly");

		socket.close();
		peer.stop();
		async.done();
	}

	/**
	 * The chunks peer streams three fixed chunks with delays; the client
	 * exercises peek (non-consuming) and readExactly (all-or-nothing) over
	 * the arriving data.
	 */
	function testChunkedReadExactlyAgainstNodePeer(async:Async) {
		if (NodePeer.skipIfUnavailable(async)) {
			return;
		}

		var peer = startPeer("chunks", ["--chunk-count", "3", "--chunk-size", "16", "--delay-ms", "30"]);
		var socket = new Socket(true);
		var connected = false;
		socket.onConnect = function() {
			connected = true;
		};

		socket.connect(peer.host, peer.port);
		Assert.isTrue(pump(socket, function() return connected, 5), "should connect against the Node peer");

		// Pump until the third chunk has landed: 3 x 16 = 48 bytes.
		Assert.isTrue(pump(socket, function() return socket.hasAvailable(48), 5), "all three chunks should arrive");

		// readExactly is all-or-nothing: more than buffered returns null.
		Assert.isNull(socket.readExactly(49), "readExactly must not consume when short");
		Assert.equals(48, socket.bytesAvailable, "a null readExactly must leave the buffer untouched");

		// peek copies without consuming.
		var peeked = socket.peekBytes(16);
		Assert.notNull(peeked);
		Assert.equals(0, peeked.get(0));
		Assert.equals(48, socket.bytesAvailable, "peekBytes must not consume");

		// Chunk i is 16 copies of byte value i.
		for (i in 0...3) {
			var chunk = socket.readExactly(16);
			Assert.notNull(chunk);
			for (j in 0...16) {
				Assert.equals(i, chunk.get(j), 'byte ${j} of chunk ${i}');
			}
		}
		Assert.equals(0, socket.bytesAvailable, "the chunks should be fully consumed");

		socket.close();
		peer.stop();
		async.done();
	}

	/**
	 * close-after-bytes: the peer sends a known payload then FINs. The data
	 * must arrive first, then the clean EOF fires onClose only — no
	 * onError/onErrorKind — and leaves the socket disconnected.
	 */
	function testNodePeerDataThenCloseFiresOnCloseOnly(async:Async) {
		if (NodePeer.skipIfUnavailable(async)) {
			return;
		}

		var peer = startPeer("close-after-bytes", ["--payload", "hex:0A0B0C0D"]);
		var socket = new Socket(true);
		var received = new BytesBuffer();
		var closeCount = 0;
		var errorCount = 0;
		var kindCount = 0;

		socket.onData = function(_) {};
		socket.onClose = function() {
			closeCount++;
		};
		socket.onError = function(msg) {
			errorCount++;
		};
		socket.onErrorKind = function(kind, msg) {
			kindCount++;
		};

		socket.connect(peer.host, peer.port);
		var start = Sys.time();
		while (Sys.time() - start < 5 && closeCount == 0 && errorCount == 0) {
			socket.poll();
			if (socket.bytesAvailable > 0) {
				var chunk = socket.readAllBytes();
				received.addBytes(chunk, 0, chunk.length);
			}
			Sys.sleep(0.005);
		}

		Assert.isTrue(received.length >= 4, "the payload should arrive before the peer closes");
		var payload = received.getBytes().sub(0, 4);
		Assert.isTrue(TestHelpers.bytesEqual(payload, Bytes.ofString("\n\x0B\x0C\x0D")), "the payload bytes must match");
		Assert.equals(0, errorCount, "a clean peer close must not fire onError");
		Assert.equals(1, closeCount, "clean peer close should fire onClose once");

		// Keep pumping briefly to confirm no error callbacks arrive late.
		var extra = Sys.time() + 0.2;
		while (Sys.time() < extra) {
			socket.poll();
			Sys.sleep(0.005);
		}
		Assert.equals(0, kindCount, "a clean peer close must not fire onErrorKind");
		Assert.equals(1, closeCount, "onClose must fire exactly once");
		Assert.isFalse(socket.connected, "the socket must be torn down after peer EOF");

		socket.close();
		peer.stop();
		async.done();
	}

	/**
	 * close-after-accept: the peer FINs immediately after accepting. The
	 * client sees onClose only, with no data and no error callbacks.
	 */
	function testNodePeerCloseAfterAcceptFiresOnCloseOnly(async:Async) {
		if (NodePeer.skipIfUnavailable(async)) {
			return;
		}

		var peer = startPeer("close-after-accept");
		var socket = new Socket(true);
		var dataCount = 0;
		var closeCount = 0;
		var errorCount = 0;
		var kindCount = 0;

		socket.onData = function(_) {
			dataCount++;
		};
		socket.onClose = function() {
			closeCount++;
		};
		socket.onError = function(msg) {
			errorCount++;
		};
		socket.onErrorKind = function(kind, msg) {
			kindCount++;
		};

		socket.connect(peer.host, peer.port);
		var start = Sys.time();
		while (Sys.time() - start < 5 && closeCount == 0 && errorCount == 0) {
			socket.poll();
			Sys.sleep(0.005);
		}

		Assert.equals(0, dataCount, "no data is expected before the immediate close");
		Assert.equals(0, errorCount, "an immediate clean close must not fire onError");
		Assert.equals(0, kindCount, "an immediate clean close must not fire onErrorKind");
		Assert.equals(1, closeCount, "clean peer close should fire onClose once");
		Assert.isFalse(socket.connected, "the socket must be torn down after peer EOF");

		socket.close();
		peer.stop();
		async.done();
	}
}
