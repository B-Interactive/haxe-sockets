package hxSockets;

import haxe.io.Bytes;

/**
 * A reusable receive buffer with separate read and write cursors.
 * Reclaims read space by compacting in place and grows only when needed,
 * so a steady stream avoids reallocating.
 */
class ReceiveBuffer {
	var _data:Bytes;
	var _readPos:Int = 0;
	var _writePos:Int = 0;
	var _maxCapacity:Int;

	/**
	 * Create a buffer with an initial capacity (it grows on demand).
	 */
	public function new(initialCapacity:Int = 4096, maxCapacity:Int = 16 * 1024 * 1024) {
		if (initialCapacity < 16) {
			initialCapacity = 16;
		}
		if (maxCapacity < initialCapacity) {
			maxCapacity = initialCapacity;
		}
		_maxCapacity = maxCapacity;
		_data = Bytes.alloc(initialCapacity);
	}

	/**
	 * Number of unread bytes currently buffered.
	 */
	public var available(get, never):Int;

	function get_available():Int {
		return _writePos - _readPos;
	}

	/**
	 * Remaining capacity before the buffer's maximum is reached (for backpressure).
	 */
	public var freeCapacity(get, never):Int;

	function get_freeCapacity():Int {
		return _maxCapacity - available;
	}

	/**
	 * Append length bytes from src (starting at srcOffset) to the buffer.
	 */
	public function write(src:Bytes, srcOffset:Int, length:Int):Void {
		if (length <= 0) {
			return;
		}
		if (srcOffset < 0 || length < 0 || srcOffset + length > src.length) {
			throw "ReceiveBuffer.write: source range out of bounds";
		}
		_ensureWritable(length);
		_data.blit(_writePos, src, srcOffset, length);
		_writePos += length;
	}

	/**
	 * Copy length unread bytes into dest, advancing the read cursor.
	 * Throws if more than available is requested.
	 */
	public function read(dest:Bytes, destOffset:Int, length:Int):Void {
		if (length <= 0) {
			return;
		}
		if (destOffset < 0 || destOffset + length > dest.length) {
			throw "ReceiveBuffer.read: destination range out of bounds";
		}
		if (length > available) {
			throw "ReceiveBuffer.read: insufficient data";
		}
		dest.blit(destOffset, _data, _readPos, length);
		_readPos += length;
		_resetIfEmpty();
	}

	/**
	 * Copy length unread bytes into dest without advancing the read cursor.
	 */
	public function peek(dest:Bytes, destOffset:Int, length:Int):Void {
		if (length <= 0) {
			return;
		}
		if (destOffset < 0 || destOffset + length > dest.length) {
			throw "ReceiveBuffer.peek: destination range out of bounds";
		}
		if (length > available) {
			throw "ReceiveBuffer.peek: insufficient data";
		}
		dest.blit(destOffset, _data, _readPos, length);
	}

	/**
	 * Read a single byte and advance the read cursor.
	 */
	public function readByte():Int {
		if (available < 1) {
			throw "ReceiveBuffer.readByte: insufficient data";
		}
		var b = _data.get(_readPos);
		_readPos++;
		_resetIfEmpty();
		return b;
	}

	/**
	 * Discard up to length unread bytes.
	 */
	public function skip(length:Int):Void {
		if (length <= 0) {
			return;
		}
		if (length > available) {
			length = available;
		}
		_readPos += length;
		_resetIfEmpty();
	}

	/**
	 * Drop all buffered data and reset both cursors (keeps the allocation).
	 */
	public function clear():Void {
		_readPos = 0;
		_writePos = 0;
	}

	function _resetIfEmpty():Void {
		// Once drained, reset cursors to the start.
		if (_readPos == _writePos) {
			_readPos = 0;
			_writePos = 0;
		}
	}

	function _ensureWritable(length:Int):Void {
		// Already fits at the tail.
		if (_writePos + length <= _data.length) {
			return;
		}

		var used = available;

		// Compact to the front if that frees enough room (no allocation).
		if (used + length <= _data.length) {
			if (_readPos > 0) {
				_data.blit(0, _data, _readPos, used);
				_readPos = 0;
				_writePos = used;
			}
			return;
		}

		// Enforce the maximum capacity before growing (also guards integer overflow).
		var needed = used + length;
		if (needed < 0 || needed > _maxCapacity) {
			throw "ReceiveBuffer: capacity limit exceeded";
		}

		// Otherwise grow the buffer, copying the live data.
		var newCapacity = _data.length;
		if (newCapacity < 16) {
			newCapacity = 16;
		}
		while (newCapacity < needed) {
			if (newCapacity > (_maxCapacity >> 1)) {
				// Next double would meet or exceed the cap; clamp and stop.
				newCapacity = _maxCapacity;
				break;
			}
			newCapacity <<= 1;
		}
		var grown = Bytes.alloc(newCapacity);
		if (used > 0) {
			grown.blit(0, _data, _readPos, used);
		}
		_data = grown;
		_readPos = 0;
		_writePos = used;
	}
}
