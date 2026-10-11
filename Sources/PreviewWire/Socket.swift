#if os(macOS)
import Darwin
import Foundation
import PreviewProtocol

// 유닉스 스트림 소켓 — 상주 연결 하나(엔진 ⟂ 호스트). 요청마다 연결을 여는 길(연결 하나 = 요청 하나 · JSON 한 줄)과 달리 연결을 열어 둔 채
// 줄과 바이너리를 오간다. 경로는 `SocketPath.forFolder`(104바이트 한계 안의 `/tmp` 짧은 이름).

public enum UnixSocket {
    public enum Failure: Error, CustomStringConvertible {
        case pathTooLong(String)
        case sys(String, Int32)
        public var description: String {
            switch self {
            case .pathTooLong(let p): "소켓 경로가 sun_path(\(SocketPath.maxBytes)바이트)를 넘는다: \(p)"
            case .sys(let what, let e): "\(what) 실패: \(String(cString: strerror(e)))"
            }
        }
    }

    /// 커널 소켓 버퍼 — macOS 기본 8 KB(`net.local.stream.sendspace`) · 최대 8 MB(`kern.ipc.maxsockbuf`).
    /// 4 MB 로 키우면 큰 프레임(수 MB)을 보내는 쓰기 · 깨우기 횟수가 줄어 엔진행이 빨라진다.
    public static let defaultBufferBytes = 4 << 20

    static func address(_ path: String) throws -> sockaddr_un {
        guard SocketPath.fits(path) else { throw Failure.pathTooLong(path) }
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        a.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &a.sun_path) { dst in
            let src = Array(path.utf8)
            dst.copyBytes(from: src)
            dst[src.count] = 0
        }
        return a
    }

    static func configure(_ fd: Int32, bufferBytes: Int?) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        if var b = bufferBytes.map(Int32.init) {
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &b, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &b, socklen_t(MemoryLayout<Int32>.size))
        }
    }

    /// 듣는 소켓 — 옛 소켓 파일은 지우고 선다(죽은 호스트가 남긴 것).
    public static func listen(path: String) throws -> Int32 {
        var a = try address(path)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.sys("socket", errno) }
        let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard r == 0 else { let e = errno; close(fd); throw Failure.sys("bind \(path)", e) }
        guard Darwin.listen(fd, 4) == 0 else { let e = errno; close(fd); throw Failure.sys("listen", e) }
        return fd
    }

    public static func accept(_ listener: Int32, bufferBytes: Int? = defaultBufferBytes) throws -> Int32 {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { throw Failure.sys("accept", errno) }
        configure(fd, bufferBytes: bufferBytes)
        return fd
    }

    public static func connect(path: String, bufferBytes: Int? = defaultBufferBytes) throws -> Int32 {
        var a = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.sys("socket", errno) }
        configure(fd, bufferBytes: bufferBytes)
        let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard r == 0 else { let e = errno; close(fd); throw Failure.sys("connect \(path)", e) }
        return fd
    }

    /// 시험용 — 이미 이어진 한 쌍.
    public static func pair(bufferBytes: Int? = defaultBufferBytes) throws -> (Int32, Int32) {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw Failure.sys("socketpair", errno) }
        configure(fds[0], bufferBytes: bufferBytes); configure(fds[1], bufferBytes: bufferBytes)
        return (fds[0], fds[1])
    }
}
#endif
