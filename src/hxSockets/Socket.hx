package hxSockets;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Eof;
import haxe.io.Error;
import haxe.Exception;
import sys.net.Host;
import sys.net.Socket as SysSocket;

/**
 * Event-driven TCP socket. Mimics the AIR SDK Socket API using native Haxe types.
 */
class Socket {
	// Events
	public var onConnect:Void->Void;
	public var onClose:Void->Void;
	public var onData:Bytes->Void;
	public var onError:String->Void;

	/**
	 * Optional typed-error callback, invoked alongside onError with a
	 * SocketErrorKind so callers can react without parsing the message.
	 */
	public var onErrorKind:SocketErrorKind->String->Void;

	// Properties
	public var bytesAvailable(get, never):Int;
	public var connected(get, never):Bool;
	public var timeout:Int = 20000; // milliseconds

	#if sys
	public var localAddress(get, never):String;
	public var localPort(get, never):Int;
	public var remoteAddress(get, never):String;
	public var remotePort(get, never):Int;
	#end

	// Private fields
	var _socket:sys.net.Socket;
	var _connected:Bool = false;

	// Protected helper method for secure socket access
	private function getSecureSocket():sys.ssl.Socket {
		return cast _socket;
	}

	var _host:String;
	var _port:Int;
	var _receiveBuffer:ReceiveBuffer;
	var _outputBuffer:BytesBuffer;
	var _pending:Bytes = null;
	var _pendingPos:Int = 0;
	var _readBuffer:Bytes;
	var _timestamp:Float;
	var _pollTimer:haxe.Timer;
	var _manualPoll:Bool;

	/**
	 * Create a socket. When manualPoll is false (default) the socket polls I/O
	 * from an internal haxe.Timer. When true, the Timer is not used and the
	 * owner must drive I/O by calling poll().
	 */
	public function new(manualPoll:Bool = false) {
		_manualPoll = manualPoll;
		_receiveBuffer = new ReceiveBuffer(4096);
		_outputBuffer = new BytesBuffer();
		_readBuffer = Bytes.alloc(4096);
	}

	/**
	 * Enable or disable manual-poll mode. Starts or stops the internal Timer
	 * to match when connected.
	 */
	public function setManualPoll(value:Bool):Void {
		if (_manualPoll == value) {
			return;
		}
		_manualPoll = value;
		if (_socket != null) {
			if (_manualPoll) {
				_stopPolling();
			} else {
				_startPolling();
			}
		}
	}

	/**
	 * Drive one I/O tick: advance connect state, read data, flush output.
	 * Used in manual-poll mode. Safe to call when not connected.
	 */
	public function poll():Void {
		_poll();
	}

	/**
	 * Connect to specified host and port
	 */
	public function connect(host:String, port:Int):Void {
		if (_socket != null) {
			close();
		}

		if (port < 0 || port > 65535) {
			_emitError(Other, "Invalid port number: " + port);
			return;
		}

		var h:Host = null;
		try {
			h = new Host(host);
		} catch (e:Dynamic) {
			_emitError(Other, "Invalid host: " + host);
			return;
		}

		_host = host;
		_port = port;
		_timestamp = Sys.time();
		_receiveBuffer.clear();

		try {
			_socket = new SysSocket();
			_socket.setBlocking(false);
			_socket.connect(h, port);
			_socket.setFastSend(true);
		} catch (e:Dynamic) {
			_emitError(Other, "Connection failed");
			return;
		}

		// Start polling (a no-op in manual-poll mode)
		_startPolling();
	}

	/**
	 * Close the socket. Idempotent; resets buffers so the instance can be
	 * re-connect()ed.
	 */
	public function close():Void {
		_stopPolling();
		if (_socket != null) {
			try {
				_socket.close();
			} catch (e:Dynamic) {}
			_socket = null;
		}
		_connected = false;
		if (_receiveBuffer != null) {
			_receiveBuffer.clear();
		}
		_outputBuffer = new BytesBuffer();
		_pending = null;
		_pendingPos = 0;
	}

	/**
	 * Write bytes to the socket
	 */
	public function writeBytes(bytes:Bytes, offset:Int = 0, length:Int = 0):Void {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		if (length == 0) {
			length = bytes.length - offset;
		}

		_outputBuffer.addBytes(bytes, offset, length);
	}

	/**
	 * Write a string to the socket (UTF-8 encoded)
	 */
	public function writeString(str:String):Void {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}
		writeBytes(Bytes.ofString(str));
	}

	/**
	 * Read length bytes from the input buffer into dest. If length is 0, reads
	 * all available bytes. Throws when no data is available.
	 */
	public function readBytes(bytes:Bytes, offset:Int = 0, length:Int = 0):Void {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		if (offset < 0 || length < 0) {
			throw new Exception("Offset or length out of bounds");
		}

		var availableLength = _receiveBuffer.available;

		if (availableLength == 0) {
			throw new Exception("There is insufficient data available to read.");
		}

		var actualLength:Int = length;
		if (length == 0) {
			actualLength = availableLength;
		} else {
			actualLength = Std.int(Math.min(length, availableLength));
		}

		if (offset + actualLength > bytes.length) {
			throw new Exception("Destination buffer too small");
		}

		try {
			_receiveBuffer.read(bytes, offset, actualLength);
		} catch (e:Dynamic) {
			throw new Exception("Error reading bytes");
		}
	}

	/**
	 * Read and consume exactly length bytes, or return null (leaving the buffer
	 * untouched) when fewer than length bytes are buffered.
	 */
	public function readExactly(length:Int):Bytes {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}
		if (length <= 0) {
			return Bytes.alloc(0);
		}
		if (_receiveBuffer.available < length) {
			return null;
		}
		var out = Bytes.alloc(length);
		_receiveBuffer.read(out, 0, length);
		return out;
	}

	/**
	 * Return true when at least length bytes are buffered for reading.
	 */
	public function hasAvailable(length:Int):Bool {
		return _receiveBuffer.available >= length;
	}

	/**
	 * Copy the next length bytes without consuming them, or return null when
	 * fewer than length bytes are buffered.
	 */
	public function peekBytes(length:Int):Bytes {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}
		if (length <= 0) {
			return Bytes.alloc(0);
		}
		if (_receiveBuffer.available < length) {
			return null;
		}
		var out = Bytes.alloc(length);
		_receiveBuffer.peek(out, 0, length);
		return out;
	}

	/**
	 * Read all available bytes from the input buffer
	 */
	public function readAllBytes():Bytes {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		var availableLength = _receiveBuffer.available;
		if (availableLength == 0) {
			throw new Exception("There is insufficient data available to read.");
		}

		var result = Bytes.alloc(availableLength);
		_receiveBuffer.read(result, 0, availableLength);
		return result;
	}

	/**
	 * Read a string from the input buffer (UTF-8 encoded)
	 */
	public function readUTFBytes(length:UInt = 0):String {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		var bytesAvail = _receiveBuffer.available;

		if (bytesAvail == 0) {
			throw new Exception("There is insufficient data available to read.");
		}

		if (length == 0) {
			length = bytesAvail;
		}

		// Ensures that if length is greater than the available bytes, it reverts to bytes available.
		var actualLength:Int = Std.int(Math.min(length, bytesAvail));

		var bytes = Bytes.alloc(actualLength);

		try {
			readBytes(bytes, 0, actualLength);
		} catch (e:Exception) {
			_emitError(Other, "Error reading UTF bytes");
			throw new Exception("Error reading UTF bytes");
		}

		return bytes.sub(0, bytes.length).toString();
	}

	/**
	 * Flush output buffer to socket
	 */
	public function flush():Void {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		// Move any queued output into the pending buffer. Check length first so
		// an empty buffer is never consumed, then getBytes() and replace it with
		// a fresh buffer for the next write.
		if (_pending == null) {
			if (_outputBuffer.length == 0) {
				return;
			}
			_pending = _outputBuffer.getBytes();
			_pendingPos = 0;
			_outputBuffer = new BytesBuffer();
		}

		try {
			var remaining = _pending.length - _pendingPos;
			var wrote = _socket.output.writeBytes(_pending, _pendingPos, remaining);
			_pendingPos += wrote;
			if (_pendingPos >= _pending.length) {
				_pending = null;
				_pendingPos = 0;
			}
		} catch (e:Dynamic) {
			switch (e) {
				case Error.Blocked | Error.Custom(Error.Blocked):
					// Send buffer full; keep _pending/_pendingPos and retry next poll.
				default:
					_emitError(ConnectionLost, "Write error");
			}
		}
	}

	// Polling logic
	function _startPolling():Void {
		_stopPolling();
		if (_manualPoll) {
			// Owner drives I/O via poll(); do not start the internal Timer.
			return;
		}
		_pollTimer = new haxe.Timer(16); // ~60fps
		_pollTimer.run = _poll;
	}

	function _stopPolling():Void {
		if (_pollTimer != null) {
			_pollTimer.stop();
			_pollTimer = null;
		}
	}

	function _poll():Void {
		if (_socket == null) {
			return;
		}

		var doConnect = false;
		var doClose = false;

		// Check connection status
		if (!_connected) {
			try {
				var r = SysSocket.select(null, [_socket], null, 0);
				if (r.write.length > 0 && r.write[0] == _socket) {
					doConnect = true;
				} else if (Sys.time() - _timestamp > timeout / 1000) {
					doClose = true;
				}
			} catch (e:Dynamic) {
				doClose = true;
			}
		}

		// Process connection
		if (doClose && !_connected) {
			close();
			_emitError(Timeout, "Connection timeout");
			return;
		}

		if (doConnect) {
			try {
				var peer = _socket.peer();
				if (peer == null) {
					// Not connected yet, check timeout
					if (Sys.time() - _timestamp > timeout / 1000) {
						close();
						_emitError(Timeout, "Connection timeout");
					}
					return;
				}
			} catch (e:Dynamic) {
				// Not connected yet, check timeout
				if (Sys.time() - _timestamp > timeout / 1000) {
					close();
					_emitError(Timeout, "Connection timeout");
				}
				return;
			}

			_connected = true;
			if (onConnect != null) {
				onConnect();
			}
		}

		// Read available data
		if (_connected) {
			try {
				var len:Int;
				// Only allocate a chunk buffer when an onData listener is set.
				var chunk:BytesBuffer = null;
				var bytesThisPoll = 0;
				final maxBytesPerPoll = 1 << 20;

				do {
					if (_receiveBuffer.freeCapacity < _readBuffer.length) {
						break; // backpressure: let the application drain before reading more
					}
					len = _socket.input.readBytes(_readBuffer, 0, _readBuffer.length);
					if (len > 0) {
						try {
							_receiveBuffer.write(_readBuffer, 0, len);
						} catch (e:Dynamic) {
							close();
							_emitError(Other, "receive buffer overflow");
							return;
						}
						if (onData != null) {
							if (chunk == null) {
								chunk = new BytesBuffer();
							}
							chunk.addBytes(_readBuffer, 0, len);
						}
						bytesThisPoll += len;
					}
				} while (len == _readBuffer.length && bytesThisPoll < maxBytesPerPoll);

				if (chunk != null && onData != null) {
					// Pass the freshly received bytes; they also stay in the buffer.
					onData(chunk.getBytes());
				}
			} catch (e:Eof) {
				close();
				if (onClose != null) {
					onClose();
				}
				if (onErrorKind != null) {
					onErrorKind(ConnectionLost, "Connection closed by peer");
				}
				return;
			} catch (e:Error) {
				switch (e) {
					case Error.Blocked | Error.Custom(Error.Blocked):
						// No data available, normal
					default:
						close();
						_emitError(ConnectionLost, "Read error");
						return;
				}
			} catch (e:Dynamic) {
				close();
				_emitError(ConnectionLost, "Read error");
				return;
			}
		}

		// Flush output buffer
		if (_connected) {
			try {
				flush();
			} catch (e:Dynamic) {
				// Error already handled in flush()
			}
		}
	}

	/**
	 * Send a failure to both onError and the optional onErrorKind callbacks.
	 */
	function _emitError(kind:SocketErrorKind, message:String):Void {
		if (onError != null) {
			onError(message);
		}
		if (onErrorKind != null) {
			onErrorKind(kind, message);
		}
	}

	// Getters
	function get_bytesAvailable():Int {
		return _receiveBuffer.available;
	}

	function get_connected():Bool {
		return _connected;
	}

	#if sys
	function get_localAddress():String {
		if (_connected && _socket != null) {
			try {
				var hostInfo = _socket.host();
				if (hostInfo != null && hostInfo.host != null) {
					return hostInfo.host.toString();
				}
			} catch (e:Dynamic) {
				// Silently fail, return null
			}
		}
		return null;
	}

	function get_localPort():Int {
		if (_connected && _socket != null) {
			try {
				var hostInfo = _socket.host();
				if (hostInfo != null) {
					return hostInfo.port;
				}
			} catch (e:Dynamic) {
				// Silently fail, return 0
			}
		}
		return 0;
	}

	function get_remoteAddress():String {
		if (_connected && _socket != null) {
			try {
				var peerInfo = _socket.peer();
				if (peerInfo != null && peerInfo.host != null) {
					return peerInfo.host.toString();
				}
			} catch (e:Dynamic) {
				// Silently fail, return null
			}
		}
		return null;
	}

	function get_remotePort():Int {
		if (_connected && _socket != null) {
			try {
				var peerInfo = _socket.peer();
				if (peerInfo != null) {
					return peerInfo.port;
				}
			} catch (e:Dynamic) {
				// Silently fail, return 0
			}
		}
		return 0;
	}
	#end
}
