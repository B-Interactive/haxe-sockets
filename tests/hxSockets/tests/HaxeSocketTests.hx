package hxSockets.tests;

import hxSockets.tests.unit.SocketBasicTests;
import hxSockets.tests.unit.SocketConnectionTests;
import hxSockets.tests.unit.SocketDataTransferTests;
import hxSockets.tests.unit.CertificateTests;
import hxSockets.tests.unit.SecureSocketTests;
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

		// Create report and run
		Report.create(runner);
		runner.run();
	}
}
