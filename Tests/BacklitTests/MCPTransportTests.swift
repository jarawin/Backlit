import XCTest
import MCP
@testable import Backlit

final class MCPTransportTests: XCTestCase {
    func testSDKClientUsesRealStdioFramingAndEOFStopsHeadlessServer() async throws {
        let input = Pipe(), output = Pipe()
        defer {
            try? input.fileHandleForReading.close(); try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        }
        let transport = BoundedMCPTransport(input:input.fileHandleForReading.fileDescriptor,output:output.fileHandleForWriting.fileDescriptor)
        let server = await BacklitMCPServer.make { _ in MCPTests.state }
        try await server.start(transport:transport)
        let client = MCP.Client(name:"stdio fixture",version:"1")
        let clientTransport = StdioTransport(input:.init(rawValue:output.fileHandleForReading.fileDescriptor),
                                             output:.init(rawValue:input.fileHandleForWriting.fileDescriptor))
        let initialized = try await client.connect(transport:clientTransport)
        XCTAssertEqual(initialized.protocolVersion,"2025-11-25")
        let listing = try await client.listTools()
        XCTAssertEqual(listing.tools.count,4)
        let response: (content:[Tool.Content],isError:Bool?) = try await client.callTool(name:"backlit_get_status")
        XCTAssertEqual(response.isError,false)
        await client.disconnect()
        try input.fileHandleForWriting.close()
        let stopped = expectation(description:"EOF completed server")
        let waiter = Task { await server.waitUntilCompleted(); stopped.fulfill() }
        await fulfillment(of:[stopped],timeout:3)
        waiter.cancel(); await server.stop()
    }
    func testFragmentedLinesAreReassembledAndTruncatedFinalLineIsDiscarded() async throws {
        let input = Pipe(), output = Pipe()
        defer {
            try? input.fileHandleForReading.close(); try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        }
        let transport = BoundedMCPTransport(input:input.fileHandleForReading.fileDescriptor,output:output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        let finished = expectation(description:"fragments and EOF")
        let reader = Task { () -> [Data] in
            var lines: [Data] = []
            for try await line in await transport.receive() { lines.append(line) }
            finished.fulfill(); return lines
        }
        try input.fileHandleForWriting.write(contentsOf:Data("{\"first\":".utf8))
        try input.fileHandleForWriting.write(contentsOf:Data("true}\n{\"second\":false}\nunfinished".utf8))
        try input.fileHandleForWriting.close()
        await fulfillment(of:[finished],timeout:3)
        reader.cancel()
        let lines = try await reader.value
        XCTAssertEqual(lines,[Data("{\"first\":true}".utf8),Data("{\"second\":false}".utf8)])
        await transport.disconnect()
    }
    func testOversizedUnterminatedMessageClosesWithoutYieldingContent() async throws {
        let input = Pipe(), output = Pipe()
        defer {
            try? input.fileHandleForReading.close(); try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        }
        let transport = BoundedMCPTransport(input:input.fileHandleForReading.fileDescriptor,output:output.fileHandleForWriting.fileDescriptor)
        try await transport.connect()
        let finished = expectation(description:"oversized input closed")
        let reader = Task { () -> Int in
            var count = 0
            for try await _ in await transport.receive() { count += 1 }
            finished.fulfill(); return count
        }
        try input.fileHandleForWriting.write(contentsOf:Data(repeating:65,count:BoundedMCPTransport.maximumMessageBytes+1))
        await fulfillment(of:[finished],timeout:3)
        reader.cancel()
        let count = try await reader.value
        XCTAssertEqual(count,0)
        await transport.disconnect()
    }
}
