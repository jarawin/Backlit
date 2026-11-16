import XCTest
import MCP
@testable import Backlit

final class SDKInitializeCompatibilityTests: XCTestCase {
    // Captured from actual Codex CLI 0.155.1 thread-runtime startup, which
    // advertises this extension unlike its separate inventory-only connection.
    static let codexInitialize = Data(#"""
    {"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"experimental":{"codex/auth-change":{}},"elicitation":{"form":{},"url":{}}},"clientInfo":{"name":"codex-mcp-client","title":"Codex","version":"0.155.1"}}}
    """#.utf8)

    func testCapturedCodexInitializeRemovesOnlyUnsupportedExperimentalCapabilities() throws {
        let normalized = SDKInitializeCompatibility.messageForSDK(Self.codexInitialize)
        var expected = try JSONDecoder().decode([String:Value].self,from:Self.codexInitialize)
        var params = try XCTUnwrap(expected["params"]?.objectValue)
        var capabilities = try XCTUnwrap(params["capabilities"]?.objectValue)
        capabilities.removeValue(forKey:"experimental")
        params["capabilities"] = .object(capabilities)
        expected["params"] = .object(params)
        XCTAssertEqual(try JSONDecoder().decode([String:Value].self,from:normalized),expected)
        let request = try JSONDecoder().decode(Request<Initialize>.self,from:normalized)
        XCTAssertEqual(request.id,.number(0))
        XCTAssertEqual(request.params.protocolVersion,"2025-06-18")
        XCTAssertEqual(request.params.clientInfo.title,"Codex")
        XCTAssertNotNil(request.params.capabilities.elicitation?.form)
        XCTAssertNotNil(request.params.capabilities.elicitation?.url)
        XCTAssertNil(request.params.capabilities.experimental)
    }

    func testNormalInitializationAndNonInitializeMessagesAreByteForByteUnchanged() {
        for message in [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"clientInfo":{"name":"fixture","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","id":"request-2","method":"tools/call","params":{"experimental":{"example":{}},"name":"fixture","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":0,"result":{"experimental":{"example":{}}}}"#,
            #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":"invalid"}"#,
            #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"capabilities":[]}}"#,
            "invalid JSON"
        ] {
            let data = Data(message.utf8)
            XCTAssertEqual(SDKInitializeCompatibility.messageForSDK(data),data)
        }
    }

    func testInvalidExperimentalTypesAreLeftUntouchedForSDKValidation() throws {
        for experimental in [Value.null,.bool(true),.int(1),.string("invalid"),.array([])] {
            let message: [String:Value] = ["jsonrpc":"2.0","id":"preserved","method":"initialize",
                "params":["capabilities":["experimental":experimental]]]
            let data = try JSONEncoder().encode(message)
            XCTAssertEqual(SDKInitializeCompatibility.messageForSDK(data),data)
        }
    }

    func testOtherCapabilitiesAndEnvelopeFieldsArePreserved() throws {
        let original = Data(#"{"jsonrpc":"2.0","id":"exact-id","method":"initialize","params":{"protocolVersion":"future-version","capabilities":{"roots":{"listChanged":true},"sampling":{"tools":{}},"experimental":{"future-extension":{"nested":[true,1,"value"]}}},"clientInfo":{"name":"future-client","version":"1"},"_meta":{"custom":"retained"}}}"#.utf8)
        let normalized = try JSONDecoder().decode([String:Value].self,
            from:SDKInitializeCompatibility.messageForSDK(original))
        XCTAssertEqual(normalized["id"],"exact-id")
        XCTAssertEqual(normalized["jsonrpc"],"2.0")
        XCTAssertEqual(normalized["method"],"initialize")
        let params = try XCTUnwrap(normalized["params"]?.objectValue)
        XCTAssertEqual(params["protocolVersion"],"future-version")
        XCTAssertEqual(params["_meta"],["custom":"retained"])
        XCTAssertEqual(params["clientInfo"],["name":"future-client","version":"1"])
        XCTAssertEqual(params["capabilities"],["roots":["listChanged":true],"sampling":["tools":[:]]])
    }

    func testCapturedCodexHandshakeAndMetadataToolListingUseActualBoundedStdio() async throws {
        let input = Pipe(), output = Pipe()
        defer {
            try? input.fileHandleForReading.close(); try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        }
        let transport = BoundedMCPTransport(input:input.fileHandleForReading.fileDescriptor,
            output:output.fileHandleForWriting.fileDescriptor)
        let client = BoundedMCPTransport(input:output.fileHandleForReading.fileDescriptor,
            output:input.fileHandleForWriting.fileDescriptor)
        let server = await BacklitMCPServer.make { _ in
            XCTFail("Startup and tool discovery must not call the light backend")
            return MCPTests.state
        }
        try await server.start(transport:transport)
        try await client.connect()
        let finished = expectation(description:"real Codex initialize and tools/list completed")
        let conversation = Task { () async throws -> [Data] in
            var iterator = await client.receive().makeAsyncIterator()
            guard let initialized = try await iterator.next() else { return [] }
            try await client.send(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
            try await client.send(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"progressToken":0}}}"#.utf8))
            guard let listing = try await iterator.next() else { return [initialized] }
            finished.fulfill()
            return [initialized,listing]
        }
        try await client.send(Self.codexInitialize)
        await fulfillment(of:[finished],timeout:3)
        conversation.cancel()
        let responses = try await conversation.value
        await client.disconnect(); await server.stop()
        XCTAssertEqual(responses.count,2)
        guard responses.count == 2 else { return }
        let initialized = try JSONDecoder().decode(Response<Initialize>.self,from:responses[0])
        XCTAssertEqual(try initialized.result.get().protocolVersion,"2025-06-18")
        let listing = try JSONDecoder().decode(Response<ListTools>.self,from:responses[1])
        XCTAssertEqual(Set(try listing.result.get().tools.map(\.name)),
            Set(["backlit_get_status","backlit_set_power","backlit_set_brightness","backlit_set_mode"]))
    }
}
