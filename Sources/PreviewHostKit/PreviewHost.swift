#if os(macOS)
import AppKit
import Foundation
import PreviewProtocol
import PreviewWire

// 모듈 `PreviewHostKit` — 런타임 갈래(macOS 전용 · 소스는 통째로 `#if os(macOS)`). 모듈 지도는 `Docs/SDK.md` §2.
//   무엇       : 미리보기 호스트 런타임 — 진입점 · 화면 등록 프로토콜 · 창 없는 렌더 · 자기 창 · 프레임 수집.
//   누가 부르나 : 프로젝트의 미리보기 호스트 실행물(`main.swift` 한 줄) · 프로젝트의 호스트 시험 · 엔진의 도구(창 없는 렌더 · 커밋 눈금).
//                앱 제품은 물지 않는다.
//   지키는 것   : 프로젝트를 모른다(등록부는 호스트 실행물이 넘긴다) · 연결 = 세션 · 엔진의 수명에 묶인다 · 프레임은 `ImageRenderer.cgImage` 바이트 그대로.
//   시작점     : `PreviewHost` · `PreviewScreen` · `PreviewSession` · `FrameRenderer`
//
// 호스트 진입점 — 프로젝트의 `main.swift` 는 이 한 줄이다: `PreviewHost.main(name:, screens:, layers:)` — 프로젝트의 데이터(IA 낱말 · 기기 틀 ·
// 빌드된 표 요약 — `PreviewProtocol` `HelloProject.swift`)를 함께 넘기면 hello 에 싣는다(`ia:` · `frames:` · `tokensBuilt:` · 없으면 싣지 않는다).
//
//   <호스트> --socket <경로>            엔진이 띄운다 · 연결을 받는다(연결 = 세션 · 여럿) · 연결이 모두 닫히면 끝난다
//   <호스트> --folder <프로젝트 폴더>    소켓 자리를 폴더 경로 해시로(`SocketPath.forFolder`)
//            [--activity none|latency]  App Nap 막기(`ProcessInfo.beginActivity` · 기본 latency)
// 모르는 인자는 건너뛴다(프로젝트의 호스트가 제 인자를 함께 받는다).
//
// 호스트는 `.accessory`(Dock 아이콘 없음) 앱으로 선다 — 창 없는 백그라운드 프로세스이고, 자기 창 모드에서만 패널을 띄운다.
// **연결 = 세션** — 듣기는 프로세스 수명 동안 열려 있어 같은 소켓 자리로 연결을 여럿 받는다(세션마다 hello · seq · 공유 메모리 · 창이 따로 — `HostListener`).
// **엔진의 수명에 묶인다** — 연결이 모두 끊기면 끝나고, 붙기 전이라도 띄운 프로세스(엔진)가 끝나면 끝난다(연결을 기다리며 고아로 남으면
// 띄운 쪽의 표준 오류를 붙들어 그 프로세스가 끝나지 않는다). 소켓 파일은 끝날 때 지운다.

public enum PreviewHost {
    package struct Config: Sendable {
        package var socket: String?
        package var activity = true

        package static func parse(_ args: [String]) -> Config {
            var c = Config()
            var i = 0
            func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
            while i < args.count {
                switch args[i] {
                case "--socket": c.socket = next()
                case "--folder": c.socket = next().map { SocketPath.forFolder($0) }
                case "--activity": c.activity = next() != "none"
                default: break
                }
                i += 1
            }
            return c
        }
    }

    nonisolated(unsafe) private static var activityToken: NSObjectProtocol?
    nonisolated(unsafe) private static var listener: HostListener?
    /// 끝날 때 지울 소켓 자리(`atexit` 손이 읽는다).
    nonisolated(unsafe) private static var socketPath: String?
    nonisolated(unsafe) private static var parentWatch: DispatchSourceProcess?

    @MainActor
    public static func main(name: String, screens: [any PreviewScreen], layers: [LayerInfo] = [],
                            ia: IAInfo? = nil, frames: [DeviceFrameInfo]? = nil, tokensBuilt: BuiltTokens? = nil,
                            arguments: [String] = CommandLine.arguments, onTokensChanged: @escaping @MainActor () -> Void = {}) -> Never {
        HostTrace.mark("main 진입")
        watchParent()
        let config = Config.parse(Array(arguments.dropFirst()))
        if config.activity {
            activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "미리보기 호스트 — 엔진의 요청에 바로 답한다")
        }
        do {
            // 소켓 · 등록부 · hello 는 NSApplication 이 필요 없다 — 앱을 세우기(창 서버 연결 — 기동에서 무거운 단계) **전에** 듣고, hello 는 받기 스레드가 보낸다
            try serve(name: name, screens: screens, layers: layers, project: (ia, frames, tokensBuilt), config: config, onTokensChanged: onTokensChanged)
        } catch {
            FileHandle.standardError.write(Data("\(ProcessInfo.processInfo.processName): \(error)\n".utf8))
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        HostTrace.mark("NSApplication 섬")
        app.run()
        exit(0)
    }

    /// 띄운 프로세스가 끝나면 끝난다 — 붙기 전에도(연결이 끊기는 길은 붙은 뒤에만 선다). 부모가 이미 없으면(launchd 가 받았다) 곧장.
    @MainActor
    private static func watchParent() {
        let parent = getppid()
        guard parent > 1 else { exit(0) }
        let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global())
        source.setEventHandler { exit(0) }
        source.resume()
        parentWatch = source
        if getppid() != parent { exit(0) }   // 거는 사이에 끝났다
    }

    @MainActor
    private static func serve(name: String, screens: [any PreviewScreen], layers: [LayerInfo],
                              project: (ia: IAInfo?, frames: [DeviceFrameInfo]?, tokensBuilt: BuiltTokens?), config: Config,
                              onTokensChanged: @escaping @MainActor () -> Void) throws {
        guard let path = config.socket else { throw PreviewHostError.noSocket }
        // 판은 이름으로 적는다(필수 인자) — 증분 빌드가 판의 변경을 이 파일의 의존으로 잡는다(`Negotiation.swift` 「기본값」).
        let hello = Hello(role: .host, protocolVersion: PreviewProtocolVersion.current, pid: getpid(), name: name, screens: try screens.map { try $0.info() },
                          layers: layers, formats: [.rgba8sRGB], ia: project.ia, frames: project.frames, tokensBuilt: project.tokensBuilt)
        HostTrace.mark("등록부 셈 끝(화면 \(screens.count))")
        let fd = try UnixSocket.listen(path: path)
        socketPath = path
        atexit { if let p = PreviewHost.socketPath { unlink(p) } }
        HostTrace.mark("소켓 들음")
        let l = HostListener(listener: fd, hello: hello, screens: screens, onTokensChanged: onTokensChanged, onEmpty: {
            // 정상 경로는 메인(끝내기 손이 소켓 파일을 지운다) · 메인이 막혔을 때의 대비 길은 소켓 파일을 지우고 곧장
            if Thread.isMainThread { exit(0) } else { if let p = PreviewHost.socketPath { unlink(p) }; _exit(0) }
        })
        listener = l
        l.start()
    }
}

/// 듣는 소켓 하나 — 연결을 받을 때마다 몸(`HostServer` — 세션 하나)을 세우고 hello 를 곧장 보낸다(받기 스레드 · NSApplication 을 세우기 전에도).
/// 듣기는 닫지 않는다(같은 자리로 다음 연결 · 엔진의 다른 표면). 세션이 닫히면 그 세션의 몸을 메인에서 거둔다(자기 창 · 공유 메모리 칸 · 세션 값).
/// 연결이 모두 닫히면 짧게 기다렸다가(`grace` — 그 사이 새 연결이 서면 계속) `onEmpty` 한 번(호스트는 끝난다) — 메인에서 부르되
/// 메인이 막혀 그 블록이 돌지 않으면 2 s 뒤 읽기 쪽에서 곧장 끝낸다(연결이 닫힌 호스트가 남아 엔진의 거둠을 세우지 않게).
package final class HostListener: @unchecked Sendable {
    let listener: Int32
    let hello: Hello
    let screens: [any PreviewScreen]
    let onTokensChanged: @MainActor () -> Void
    let onEmpty: @Sendable () -> Void
    /// 마지막 연결이 닫힌 뒤 끝내기 전 기다리는 시간(초) — 엔진이 같은 자리로 다시 붙는 사이.
    let grace: Double
    private let lock = NSLock()
    private var servers: [ObjectIdentifier: HostServer] = [:]
    private var opened = 0
    private var fired = false
    private var stopped = false

    package init(listener: Int32, hello: Hello, screens: [any PreviewScreen], onTokensChanged: @escaping @MainActor () -> Void,
                 grace: Double = 0.5, onEmpty: @escaping @Sendable () -> Void) {
        self.listener = listener; self.hello = hello; self.screens = screens; self.onTokensChanged = onTokensChanged; self.grace = grace; self.onEmpty = onEmpty
    }

    /// 지금 열린 연결(세션) 수.
    package var live: Int { lock.withLock { servers.count } }
    /// 지금 열린 세션의 몸들(차례 없음).
    func sessions() -> [HostServer] { lock.withLock { Array(servers.values) } }
    /// 지금까지 받은 연결 수.
    package var accepted: Int { lock.withLock { opened } }

    /// 받기 스레드를 세운다 — 연결마다 몸 하나.
    package func start() {
        Thread.detachNewThread { [self] in
            while true {
                let fd: Int32
                do { fd = try UnixSocket.accept(listener) } catch {
                    if lock.withLock({ stopped }) { return }
                    FileHandle.standardError.write(Data("\(ProcessInfo.processInfo.processName): \(error)\n".utf8))
                    if live == 0 { exit(1) } else { return }
                }
                let s = HostServer(screens: screens, onTokensChanged: onTokensChanged)
                let key = ObjectIdentifier(s)
                lock.withLock { servers[key] = s; opened += 1 }
                do {
                    try s.attach(Connection(fd: fd), hello: hello, onClose: { [self] in closed(key) })
                } catch {
                    FileHandle.standardError.write(Data("\(ProcessInfo.processInfo.processName): \(error)\n".utf8))
                    closed(key)
                }
            }
        }
    }

    /// 듣기를 닫는다 — 받기 스레드가 조용히 끝난다(열린 세션은 그대로).
    package func stop() {
        lock.withLock { stopped = true }
        Darwin.shutdown(listener, SHUT_RDWR)
        close(listener)
    }

    private func closed(_ key: ObjectIdentifier) {
        let (gone, left) = lock.withLock { (servers.removeValue(forKey: key), servers.count) }
        // 닫힌 세션의 몸을 메인에서 거둔다 — 자기 창은 소유자가 풀려도 화면에 남는다(활성화하지 않는 패널)
        if let gone { DispatchQueue.main.async { MainActor.assumeIsolated { gone.shutdown() } } }
        guard left == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + grace) { [self] in fireIfEmpty() }
        DispatchQueue.global().asyncAfter(deadline: .now() + grace + 2) { [self] in fireIfEmpty() }
    }

    /// 연결이 하나도 없으면 `onEmpty` 한 번.
    private func fireIfEmpty() {
        let go = lock.withLock { () -> Bool in
            guard servers.isEmpty, !fired else { return false }
            fired = true
            return true
        }
        if go { onEmpty() }
    }
}
#endif
