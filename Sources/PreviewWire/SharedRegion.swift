#if os(macOS)
import CShm
import Darwin
import Foundation
import PreviewProtocol

// 공유 메모리 칸 — 전송 B. 엔진이 만들고(호스트가 죽어도 남는다 · 재기동한 호스트가 같은 자리를 다시 연다) 호스트가 연다.
// 호스트는 칸에 **바로 렌더**하고(CGContext 의 data = 칸) 소켓에는 칸 번호만 보낸다. 엔진은 칸 위에 CGImage 를 복사 없이 세운다.
//
//   posix : `shm_open` + `ftruncate` + `mmap` — 이름은 `/` 로 시작 · 31바이트 한계(PSHMNAMLEN). macOS 는 ftruncate 를 한 번만 받는다
//           (크기를 바꾸려면 새 이름으로 다시 만든다).
//   file  : `/tmp` 파일 + `mmap(MAP_SHARED)` — 크기 바꾸기 자유 · 디스크 파일에 기댄 페이지. 왕복 · 뒤처짐은 posix 와 같다.
// IOSurface 는 프로세스 넘기기가 mach port(XPC)라 유닉스 소켓 위로는 못 넘긴다(전역 조회 `kIOSurfaceIsGlobal` 은 폐기).

public final class SharedRegion: @unchecked Sendable {
    public let info: SharedMemoryInfo
    public let base: UnsafeMutableRawPointer
    private let owner: Bool

    public enum Failure: Error, CustomStringConvertible {
        case sys(String, Int32)
        case nameTooLong(String)
        /// 이 SDK 가 모르는 전송 종류(`SharedMemoryInfo.Kind`).
        case unknownKind(String)
        public var description: String {
            switch self {
            case .sys(let w, let e): "\(w) 실패: \(String(cString: strerror(e)))"
            case .nameTooLong(let n): "shm 이름이 31바이트를 넘는다: \(n)"
            case .unknownKind(let k): "모르는 공유 메모리 종류: \(k)"
            }
        }
    }

    /// 엔진 쪽 — 새로 만든다(같은 이름이 남아 있으면 지우고).
    public static func create(_ info: SharedMemoryInfo) throws -> SharedRegion {
        let fd: Int32
        switch info.kind {
        case .posix:
            guard info.name.utf8.count <= 31 else { throw Failure.nameTooLong(info.name) }
            shm_unlink(info.name)
            fd = cshm_open(info.name, O_CREAT | O_EXCL | O_RDWR, 0o600)
        case .file:
            unlink(info.name)
            fd = Darwin.open(info.name, O_CREAT | O_EXCL | O_RDWR, 0o600)
        default:
            throw Failure.unknownKind(info.kind.rawValue)
        }
        guard fd >= 0 else { throw Failure.sys("열기 \(info.name)", errno) }
        defer { close(fd) }
        guard ftruncate(fd, off_t(info.totalBytes)) == 0 else { throw Failure.sys("ftruncate", errno) }
        return try SharedRegion(info: info, fd: fd, owner: true)
    }

    /// 호스트 쪽 — 엔진이 만든 것을 연다.
    public static func open(_ info: SharedMemoryInfo) throws -> SharedRegion {
        let fd: Int32
        switch info.kind {
        case .posix: fd = cshm_open(info.name, O_RDWR, 0o600)
        case .file: fd = Darwin.open(info.name, O_RDWR)
        default: throw Failure.unknownKind(info.kind.rawValue)
        }
        guard fd >= 0 else { throw Failure.sys("열기 \(info.name)", errno) }
        defer { close(fd) }
        return try SharedRegion(info: info, fd: fd, owner: false)
    }

    private init(info: SharedMemoryInfo, fd: Int32, owner: Bool) throws {
        let p = mmap(nil, info.totalBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard let p, p != MAP_FAILED else { throw Failure.sys("mmap", errno) }
        self.info = info; self.base = p; self.owner = owner
    }

    deinit {
        munmap(base, info.totalBytes)
        if owner {
            switch info.kind {
            case .posix: shm_unlink(info.name)
            case .file: unlink(info.name)
            default: break
            }
        }
    }

    public func slot(_ i: Int) -> UnsafeMutableRawPointer {
        precondition(i >= 0 && i < info.slots)
        return base + i * info.slotBytes
    }

    /// 엔진이 쓸 짧은 이름 — `/mucp.<pid>.<n>`(posix 31바이트 안) · `/tmp/mucp.<pid>.<n>.shm`(file).
    public static func name(kind: SharedMemoryInfo.Kind, tag: Int) -> String {
        let pid = getpid()
        return kind == .posix ? "/mucp.\(pid).\(tag)" : "/tmp/mucp.\(pid).\(tag).shm"
    }
}
#endif
