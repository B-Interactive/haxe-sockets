package hxSockets.tests.unit;

import utest.Test;
import utest.Assert;
import hxSockets.ReceiveBuffer;
import haxe.io.Bytes;

/**
 * Tests for ReceiveBuffer. Pure unit tests, no network required.
 */
class ReceiveBufferTests extends Test {
	function bytesOf(values:Array<Int>):Bytes {
		var b = Bytes.alloc(values.length);
		for (i in 0...values.length) {
			b.set(i, values[i]);
		}
		return b;
	}

	function testEmpty() {
		var buf = new ReceiveBuffer(16);
		Assert.equals(0, buf.available);
	}

	function testWriteThenRead() {
		var buf = new ReceiveBuffer(16);
		var src = bytesOf([1, 2, 3, 4, 5]);
		buf.write(src, 0, 5);
		Assert.equals(5, buf.available);

		var dest = Bytes.alloc(5);
		buf.read(dest, 0, 5);
		Assert.equals(0, buf.available);
		for (i in 0...5) {
			Assert.equals(i + 1, dest.get(i));
		}
	}

	function testPartialReadAdvancesCursor() {
		var buf = new ReceiveBuffer(16);
		buf.write(bytesOf([10, 20, 30, 40]), 0, 4);

		var dest = Bytes.alloc(2);
		buf.read(dest, 0, 2);
		Assert.equals(10, dest.get(0));
		Assert.equals(20, dest.get(1));
		Assert.equals(2, buf.available);

		buf.read(dest, 0, 2);
		Assert.equals(30, dest.get(0));
		Assert.equals(40, dest.get(1));
		Assert.equals(0, buf.available);
	}

	function testPeekIsNonDestructive() {
		var buf = new ReceiveBuffer(16);
		buf.write(bytesOf([7, 8, 9]), 0, 3);

		var peeked = Bytes.alloc(3);
		buf.peek(peeked, 0, 3);
		Assert.equals(3, buf.available); // unchanged
		Assert.equals(7, peeked.get(0));
		Assert.equals(8, peeked.get(1));
		Assert.equals(9, peeked.get(2));

		// A subsequent read returns the same data.
		var read = Bytes.alloc(3);
		buf.read(read, 0, 3);
		Assert.equals(7, read.get(0));
		Assert.equals(9, read.get(2));
	}

	function testReadByteAndSkip() {
		var buf = new ReceiveBuffer(16);
		buf.write(bytesOf([100, 101, 102, 103]), 0, 4);

		Assert.equals(100, buf.readByte());
		Assert.equals(3, buf.available);

		buf.skip(2);
		Assert.equals(1, buf.available);
		Assert.equals(103, buf.readByte());
		Assert.equals(0, buf.available);
	}

	function testInterleavedWriteReadStaysCorrect() {
		var buf = new ReceiveBuffer(8);
		var counter = 0;
		var expected = 0;

		// Write a block and drain part of it repeatedly to exercise compaction.
		for (round in 0...50) {
			var block = Bytes.alloc(5);
			for (i in 0...5) {
				block.set(i, (counter++) % 256);
			}
			buf.write(block, 0, 5);

			var dest = Bytes.alloc(3);
			buf.read(dest, 0, 3);
			for (i in 0...3) {
				Assert.equals(expected % 256, dest.get(i));
				expected++;
			}
		}
	}

	function testGrowBeyondInitialCapacity() {
		var buf = new ReceiveBuffer(16);
		var big = Bytes.alloc(1000);
		for (i in 0...1000) {
			big.set(i, i % 256);
		}
		buf.write(big, 0, 1000);
		Assert.equals(1000, buf.available);

		var out = Bytes.alloc(1000);
		buf.read(out, 0, 1000);
		for (i in 0...1000) {
			Assert.equals(i % 256, out.get(i));
		}
	}

	function testClearResets() {
		var buf = new ReceiveBuffer(16);
		buf.write(bytesOf([1, 2, 3]), 0, 3);
		buf.clear();
		Assert.equals(0, buf.available);

		// Reusable after clear.
		buf.write(bytesOf([9, 9]), 0, 2);
		Assert.equals(2, buf.available);
	}

	function testReadTooMuchThrows() {
		var buf = new ReceiveBuffer(16);
		buf.write(bytesOf([1, 2]), 0, 2);
		Assert.raises(function() {
			var dest = Bytes.alloc(4);
			buf.read(dest, 0, 4);
		}, String);
	}
}
