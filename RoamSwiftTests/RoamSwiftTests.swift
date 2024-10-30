//
//  RoamSwiftTests.swift
//  RoamSwiftTests
//
//  Created by Scott Driggers on 10/29/24.
//

import Testing
import Roam

struct RoamSwiftTests {

    @Test func testAddressableInterfaceRange() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        let simulatedIface = Addressed4NetworkInterface(
            name: "Sim",
            family: 2,
            address: IP4Address(string: "172.16.33.239")!, netmask: IP4Address(string: "255.255.254.0")!, flags: 34915, nwInterface: nil)

        let range = simulatedIface.scannableIPV4NetworkRange
        let count = range.count
        let start = range.lowerBound
        let end = range.upperBound

        #expect(count == 511)
        #expect(start == IP4Address(string: "172.16.32.0")!)
        #expect(end == IP4Address(string: "172.16.33.255")!)
    }

}
