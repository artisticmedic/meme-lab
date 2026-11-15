import Darwin
import Foundation

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data

    static func json<T: Encodable>(_ value: T) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: (try? JSONFile.encoder().encode(value)) ?? Data())
    }

    static func text(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(message.utf8))
    }
}

/// A small HTTP/1.1 server on 127.0.0.1, one request per connection.
final class HTTPServer: @unchecked Sendable {
    let port: UInt16
    private let socketFD: Int32
    private let handler: @Sendable (HTTPRequest) -> HTTPResponse

    init(port: UInt16 = 0, handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse) throws {
        signal(SIGPIPE, SIG_IGN)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MemeError("Could not open a socket for the picker page.") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 32) == 0 else {
            close(fd)
            throw MemeError("Could not listen on 127.0.0.1:\(port) for the picker page.")
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        self.socketFD = fd
        self.port = UInt16(bigEndian: actual.sin_port)
        self.handler = handler
    }

    func start() {
        let thread = Thread { [self] in
            while true {
                let client = accept(socketFD, nil, nil)
                if client < 0 { if errno == EINTR { continue } else { return } }
                var yes: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
                DispatchQueue.global().async { self.serve(client) }
            }
        }
        thread.start()
    }

    func stop() { close(socketFD) }

    private func serve(_ client: Int32) {
        defer { close(client) }
        guard let request = Self.read(client) else { return }
        let response = handler(request)
        Self.write(response, to: client, head: request.method == "HEAD")
    }

    static func read(_ client: Int32) -> HTTPRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        let separator = Data("\r\n\r\n".utf8)
        var headerEnd: Range<Data.Index>?
        while headerEnd == nil {
            let n = recv(client, &chunk, chunk.count, 0)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            headerEnd = buffer.range(of: separator)
            if buffer.count > 1_048_576 { return nil }
        }
        let head = String(decoding: buffer[..<headerEnd!.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var body = Data(buffer[headerEnd!.upperBound...])
        let length = min(Int(headers["content-length"] ?? "0") ?? 0, 1_048_576)
        while body.count < length {
            let n = recv(client, &chunk, chunk.count, 0)
            if n <= 0 { break }
            body.append(contentsOf: chunk[0..<n])
        }
        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return HTTPRequest(
            method: String(requestLine[0]), path: components?.percentEncodedPath.removingPercentEncoding ?? target,
            query: query, headers: headers, body: body
        )
    }

    static func write(_ response: HTTPResponse, to client: Int32, head: Bool) {
        let reasons = [200: "OK", 206: "Partial Content", 302: "Found", 400: "Bad Request", 403: "Forbidden",
                       404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 416: "Range Not Satisfiable"]
        var text = "HTTP/1.1 \(response.status) \(reasons[response.status] ?? "OK")\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        headers["Cache-Control"] = headers["Cache-Control"] ?? "no-store"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { text += "\(name): \(value)\r\n" }
        text += "\r\n"
        var data = Data(text.utf8)
        if !head { data.append(response.body) }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = send(client, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if n <= 0 { return }
                offset += n
            }
        }
    }
}
