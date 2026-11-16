import XCTest
import Network
@testable import Backlit

final class MCPHTTPClientTests: XCTestCase {
    @MainActor private func responder(status: String = "200 OK", headers: String = "", body: Data,
                                      onConnection: (() -> Void)? = nil) async throws -> (NWListener, UInt16) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:.ipv4(.loopback),port:.any)
        let listener = try NWListener(using:parameters)
        let ready = expectation(description:"isolated HTTP responder")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        var response = Data("HTTP/1.1 \(status)\r\n\(headers)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        let bytes = response
        let queue = DispatchQueue(label:"Backlit.MCPHTTPFixture")
        listener.newConnectionHandler = { connection in
            onConnection?()
            connection.start(queue:queue)
            connection.receive(minimumIncompleteLength:1,maximumLength:16384) { _,_,_,_ in
                connection.send(content:bytes,completion:.contentProcessed{_ in connection.cancel()})
            }
        }
        listener.start(queue:queue)
        await fulfillment(of:[ready],timeout:3)
        let port = try XCTUnwrap(listener.port?.rawValue)
        XCTAssertNotEqual(port,48261)
        return (listener,port)
    }
    @MainActor func testRedirectDoesNotForwardCredentialOrReachAnotherListener() async throws {
        let reached = expectation(description:"redirect target must not receive a request"); reached.isInverted = true
        let (sink,sinkPort) = try await responder(body:Data("{}".utf8),onConnection:{reached.fulfill()})
        defer { sink.cancel() }
        let (source,sourcePort) = try await responder(status:"302 Found",headers:"Location: http://127.0.0.1:\(sinkPort)/other\r\n",body:Data())
        defer { source.cancel() }
        let client = MCPBridgeClient(port:sourcePort,token:{"fixture-only-key"})
        do { _ = try await client.request(nil); XCTFail("Redirect accepted") }
        catch { XCTAssertEqual((error as? ExternalControlError)?.code,.unavailable) }
        await fulfillment(of:[reached],timeout:0.1)
    }
    @MainActor func testResponseSizeIsBoundedEvenWhenServerClaimsSuccess() async throws {
        let (server,port) = try await responder(body:Data(repeating:65,count:32769))
        defer { server.cancel() }
        let client = MCPBridgeClient(port:port,token:{"fixture-only-key"})
        do { _ = try await client.request(nil); XCTFail("Oversized response accepted") }
        catch {
            XCTAssertEqual((error as? ExternalControlError)?.code,.unavailable)
            XCTAssertTrue(error.localizedDescription.contains("oversized"))
        }
    }
    @MainActor func testMalformedSuccessfulResponseCannotMasqueradeAsAppliedState() async throws {
        let (server,port) = try await responder(body:Data(#"{"enabled":true,"application_result":"applied"}"#.utf8))
        defer { server.cancel() }
        let client = MCPBridgeClient(port:port,token:{"fixture-only-key"})
        do { _ = try await client.request(nil); XCTFail("Incomplete state accepted") }
        catch { XCTAssertEqual((error as? ExternalControlError)?.code,.unavailable) }
    }
}
