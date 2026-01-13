package hxSockets;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Eof;
import haxe.io.Error;
import haxe.Exception;
import sys.net.Host;
import sys.net.Socket as SysSocket;

/**
 * Event-driven TCP socket implementation for Haxe
 * Mimics AIR SDK Socket API while using native Haxe types
 */
class Socket {
	// Events
	public var onConnect:Void->Void;
	public var onClose:Void->Void;
	public var onData:Bytes->Void;
	public var onError:String->Void;

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
	var _inputBuffer:BytesBuffer;
	var _receivedBytes:Bytes;
	var _outputBuffer:BytesBuffer;
	var _readBuffer:Bytes;
	var _timestamp:Float;
	var _pollTimer:haxe.Timer;

	public function new() {
		_inputBuffer = new BytesBuffer();
		_receivedBytes = Bytes.alloc(0);
		_outputBuffer = new BytesBuffer();
		_readBuffer = Bytes.alloc(4096);
	}

	/**
	 * Connect to specified host and port
	 */
	public function connect(host:String, port:Int):Void {
		if (_socket != null) {
			close();
		}

		if (port < 0 || port > 65535) {
			if (onError != null) {
				onError("Invalid port number: " + port);
			}
			return;
		}

		var h:Host = null;
		try {
			h = new Host(host);
		} catch (e:Dynamic) {
			if (onError != null) {
				onError("Invalid host: " + host);
			}
			return;
		}

		_host = host;
		_port = port;
		_timestamp = Sys.time();

		try {
			_socket = new SysSocket();
			_socket.setBlocking(false);
			_socket.connect(h, port);
			_socket.setFastSend(true);
		} catch (e:Dynamic) {
			if (onError != null) {
				onError("Connection failed: " + e);
			}
			return;
		}

		// Start polling
		_startPolling();
	}

	/**
	 * Close the socket connection
	 */
	public function close():Void {
		if (_socket != null) {
			_stopPolling();
			try {
				_socket.close();
			} catch (e:Dynamic) {}
			_socket = null;
			_connected = false;
		}
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
	 * Read bytes from the input buffer
	 */
	public function readBytes(bytes:Bytes, offset:UInt = 0, length:UInt = 0):Void {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		// Calculate actual length to read
		var availableLength = _receivedBytes.length;

		if (availableLength == 0) {
			throw new Exception("There is insufficient data available to read.");
		}

		// Check if offset is valid
		if (offset < 0 || offset >= availableLength) {
			throw new Exception("Offset out of bounds");
		}

		var actualLength:Int = length;
		if (length == 0) {
			actualLength = availableLength - offset;
		} else {
			actualLength = Std.int(Math.min(length, availableLength - offset));
		}

		// Copy data to provided buffer
		try {
			bytes.blit(offset, _receivedBytes, offset, actualLength);
		} catch (e:Dynamic) {
			throw new Exception("Error writing bytes: " + e);
		}

		// Update _receivedBytes to remove the read portion
		var remainingBytes = availableLength - (offset + actualLength);
		if (remainingBytes > 0) {
			var newReceivedBytes:Bytes = Bytes.alloc(remainingBytes);
			newReceivedBytes.blit(0, _receivedBytes, offset + actualLength, remainingBytes);
			_receivedBytes = newReceivedBytes;
		} else {
			_receivedBytes = Bytes.alloc(0);
		}
	}

	/**
	 * Read all available bytes from the input buffer
	 */
	public function readAllBytes():Bytes {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		if (_receivedBytes.length == 0) {
			throw new Exception("There is insufficient data available to read.");
		}

		var result = Bytes.alloc(_receivedBytes.length);
		result.blit(0, _receivedBytes, 0, _receivedBytes.length);
		_receivedBytes = Bytes.alloc(0);

		return result;
	}

	/**
	 * Read a string from the input buffer (UTF-8 encoded)
	 */
	public function readUTFBytes(length:UInt = 0):String {
		if (_socket == null) {
			throw new Exception("An I/O error occurred on the socket, or the socket is not open.");
		}

		var bytesAvail = _receivedBytes.length;

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
			trace("Error performing readUTFBytes() : " + e);
			return "";
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

		var outputBytes = _outputBuffer.getBytes();
		if (outputBytes.length > 0) {
			try {
				_socket.output.writeBytes(outputBytes, 0, outputBytes.length);
				_outputBuffer = new BytesBuffer();
			} catch (e:Dynamic) {
				switch (e) {
					case Error.Blocked | Error.Custom(Error.Blocked):
						// Buffer is full, try again later
					default:
						if (onError != null) {
							onError("Write error: " + e);
						}
				}
			}
		}
	}

	// Polling logic
	function _startPolling():Void {
		_stopPolling();
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
			if (onError != null) {
				onError("Connection timeout");
			}
			return;
		}

		if (doConnect) {
			try {
				var peer = _socket.peer();
				if (peer == null) {
					// Not connected yet, check timeout
					if (Sys.time() - _timestamp > timeout / 1000) {
						close();
						if (onError != null) {
							onError("Connection timeout");
						}
					}
					return;
				}
			} catch (e:Dynamic) {
				// Not connected yet, check timeout
				if (Sys.time() - _timestamp > timeout / 1000) {
					close();
					if (onError != null) {
						onError("Connection timeout");
					}
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
				var hasData = false;
				var len:Int;

				do {
					len = _socket.input.readBytes(_readBuffer, 0, _readBuffer.length);
					if (len > 0) {
						_inputBuffer.addBytes(_readBuffer, 0, len);
						hasData = true;
					}
				} while (len == _readBuffer.length);

				if (hasData && onData != null) {
					var inputBytes = _inputBuffer.getBytes();

					// Create a new Bytes object large enough for old + new data
					var newReceivedBytes = Bytes.alloc(_receivedBytes.length + inputBytes.length);

					// Copy existing data
					if (_receivedBytes.length > 0) {
						newReceivedBytes.blit(0, _receivedBytes, 0, _receivedBytes.length);
					}

					// Append new data
					newReceivedBytes.blit(_receivedBytes.length, inputBytes, 0, inputBytes.length);

					// Replace the old buffer
					_receivedBytes = newReceivedBytes;

					// Reset input buffer after transferring data
					_inputBuffer = new BytesBuffer();

					// Call onData callback with the new bytes
					onData(inputBytes);
				}
			} catch (e:Eof) {
				close();
				if (onClose != null) {
					onClose();
				}
				return;
			} catch (e:Error) {
				switch (e) {
					case Error.Blocked | Error.Custom(Error.Blocked):
						// No data available, normal
					default:
						close();
						if (onError != null) {
							onError("Read error: " + e);
						}
						return;
				}
			} catch (e:Dynamic) {
				close();
				if (onError != null) {
					onError("Read error: " + e);
				}
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

	// Getters
	function get_bytesAvailable():Int {
		return _receivedBytes.length;
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
