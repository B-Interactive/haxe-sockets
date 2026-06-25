package hxSockets.tests;

import hxSockets.tests.unit.SocketBasicTests;
import hxSockets.tests.unit.SocketConnectionTests;
import hxSockets.tests.unit.SocketDataTransferTests;
import hxSockets.tests.unit.CertificateTests;
import hxSockets.tests.unit.SecureSocketTests;
import hxSockets.tests.unit.ReceiveBufferTests;
#if (cpp || neko || hl)
import hxSockets.tests.unit.FramedReadTests;
import hxSockets.tests.unit.ManualPollTests;
import hxSockets.tests.unit.MtlsTests;
#end
import utest.Runner;
import utest.ui.Report;

/**
 * Main test runner for hxSockets library
 */
class HaxeSocketTests {
	public static function main() {
		var runner = new Runner();

		// Add all test cases
		runner.addCase(new SocketBasicTests());
		runner.addCase(new SocketConnectionTests());
		runner.addCase(new SocketDataTransferTests());
		runner.addCase(new CertificateTests());
		runner.addCase(new SecureSocketTests());

		// Pure unit tests for the non-reallocating receive buffer (all targets).
		runner.addCase(new ReceiveBufferTests());

		// Tests needing a local loopback / TLS server and threads are sys-only
		// (built and run on the C++ target per the library's test conventions).
		#if (cpp || neko || hl)
		runner.addCase(new FramedReadTests());
		runner.addCase(new ManualPollTests());
		runner.addCase(new MtlsTests());
		#end

		// Create report and run
		Report.create(runner);
		runner.run();
	}
}
