//
//  RoamSwiftTests.swift
//  RoamSwiftTests
//
//  Created by Scott Driggers on 10/29/24.
//

import Testing
import Roam
import Foundation

struct RoamSwiftTests {
    @Test func testRokuAppsDecodeElementTextName() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <apps>
            <app id="tvinput.hdmi2" type="tvin" version="1.0.0">Nintendo Switch</app>
            <app id="41468" type="appl" subtype="sdka" version="3.9.2">Tubi - Free Movies &amp; TV</app>
        </apps>
        """

        let apps = try XMLStreamDecoder().decode([AppLink].self, from: Data(xml.utf8))
        let encodedApps = try JSONSerialization.jsonObject(with: JSONEncoder().encode(apps)) as? [[String: Any]]

        #expect(apps.map(\.id) == ["tvinput.hdmi2", "41468"])
        #expect(encodedApps?.compactMap { $0["name"] as? String } == ["Nintendo Switch", "Tubi - Free Movies & TV"])
        #expect(apps.map(\.type) == ["tvin", "appl"])
        #expect(apps.allSatisfy { $0.deviceId.isEmpty })
    }

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

    @Test func testAddressableInterfaceRangePrefersLocalSubnet() async throws {
        let simulatedIface = Addressed4NetworkInterface(
            name: "Sim",
            family: 2,
            address: IP4Address(string: "192.168.10.22")!, netmask: IP4Address(string: "255.255.0.0")!, flags: 34915, nwInterface: nil)

        let scanRange = Array(simulatedIface.scannableIPV4NetworkRange)
        let prioritizedRange = simulatedIface.preferredScannableIPV4Ranges.flatMap { Array($0) }

        #expect(prioritizedRange.count == scanRange.count)
        #expect(prioritizedRange.sorted() == scanRange)
        #expect(prioritizedRange[0] == IP4Address(string: "192.168.10.0")!)
        #expect(prioritizedRange[22] == IP4Address(string: "192.168.10.22")!)
        #expect(prioritizedRange[255] == IP4Address(string: "192.168.10.255")!)
        #expect(prioritizedRange[256] == IP4Address(string: "192.168.0.0")!)
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

    @Test func testConnectRegex() async throws {
        let connectTestCases = [
            "looking for my roku tv",
            "hi yes it wont connect to my tv",
            "Hola no me conecta a mi tele",
            "Cómo puedo conectar mi TV  Ami celular",
            "كيف اشغل الجهاز",
            "Tôi không thể kết nối với TV bằng đồng hồ",
            "Como conectarme a una pantalla ?",
            "I keep putting the IP address but it's not working",
            "I am trying to control my TV, but it is not connecting, and it says that the TV is not on",
            "Why can't I find my tv",
            "How can I get my Roku to connect?",
            "كيف اشبكه مع التلفزيون",
            "No puedo conectar mi televisión",
            "how can i find. a roku device",
            "it wont find my tv",
            "the roku wont pick up my tv only my tv in the other room",
            "I am trying to connect my 55 inch Roku TV to this app and it's not working. I added my number thing and it's not working.",
            "Your app is not working. I have my TV connected to the app, but when I press the button it don't work",
            "Hi Scott, I put in the IP Address, and it said the name of my Roku, but no buttons work. Please help",
        ]

        let thirdPartyTestCases = [
            "Why. Isn't my app working",
            "im trying to use the remote app on my tv but it isn't working",
            "It only lets me turn up and down the volume",
            "I can only turn the sound on my tv from my watch and nothing",
            "It won't let me use any buttons except for the volume buttons in the home button",
            "I can turn my TV up and down, but it won't let me do anything else",
            "Why won't it work when I push the up and down buttons but then when I push the volume buttons it works",
        ]

        // Test that all connect test cases return RoboMessage.cantConnect
        for testCase in connectTestCases {
            let result = await checkRoboMessage(testCase)
            #expect(result == .cantConnect, "Expected .cantConnect for: '\(testCase)', but got: \(String(describing: result))")
        }

        // Test that all third party test cases return RoboMessage.thirdPartyApps
        for testCase in thirdPartyTestCases {
            let result = await checkRoboMessage(testCase)
            #expect(result == .thirdPartyApps, "Expected .thirdPartyApps for: '\(testCase)', but got: \(String(describing: result))")
        }

        // Test cases that should return nil (no match)
        let noMatchTestCases = [
            "Hello there",
            "What's the weather like?",
            "How are you doing today?",
            "Can you help me with math?",
            "Random message that doesn't match any pattern",
            "",
            "   ", // whitespace only
        ]

        for testCase in noMatchTestCases {
            let result = await checkRoboMessage(testCase)
            #expect(result == nil, "Expected nil for: '\(testCase)', but got: \(String(describing: result))")
        }
    }
}
