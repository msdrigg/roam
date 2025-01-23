//
//  RoamSwiftTests.swift
//  RoamSwiftTests
//
//  Created by Scott Driggers on 10/29/24.
//

import Testing
import Roam

struct RoamSwiftTests {
    @Test func testWebsocketHeaderdecoding() async throws {
        let hexHeader = "817e1312"
        let data = Data(hexString: hexHeader)!

        let header = WebsocketHeader.parse(from: data)!

        #expect(header.opcode == 0x01, "Opcode should be text")
        #expect(header.payloadLength == 4882, "Payload should be 4882")

        let hexHeader10b = "817f00000000000191b5"
        let data2 = Data(hexString: hexHeader10b)!

        let header2 = WebsocketHeader.parse(from: data2)!

        #expect(header2.opcode == 0x01, "Opcode should be text")
        #expect(header2.payloadLength == 102837, "Payload should be 4882")
    }

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

    @Test func testKebabify() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        let res1 = kebabify("TestingKebabifyParam")
        let res2 = kebabify("testingKebabifyParam2")
        let res3 = kebabify("TestingKebabifyParamMULTIPLE")

        #expect(res1 == "testing-kebabify-param")
        #expect(res2 == "testing-kebabify-param2")
        #expect(res3 == "testing-kebabify-param-multiple")
    }
}
