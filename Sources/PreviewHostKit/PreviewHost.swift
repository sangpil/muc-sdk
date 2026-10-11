#if os(macOS)
import AppKit
import Foundation
import PreviewProtocol
import PreviewWire

// 호스트 진입점 — 프로젝트의 `main.swift` 는 이 한 줄이다: `PreviewHost.main(name:, screens:, layers:)` — 프로젝트의 데이터(IA 낱말 · 기기 틀 ·
// 빌드된 표 요약 — `PreviewProtocol` `HelloProject.swift`)를 함께 넘기면 hello 에 싣는다(`ia:` · `frames:` · `tokensBuilt:` · 없으면 싣지 않는다).
//
//   <호스트> --socket <경로>            엔진이 띄운다 · 연결 하나를 받고 엔진이 떠나면 끝난다
//   <호스트> --folder <프로젝트 폴더>    소켓 자리를 폴더 경로 해시로(`SocketPath.forFolder`)
//            [--activity none|latency]  App Nap 막기(`ProcessInfo.beginActivity` · 기본 latency)
// 모르는 인자는 건너뛴다(프로젝트의 호스트가 제 인자를 함께 받는다).
//
// 호스트는 `.accessory`(Dock 아이콘 없음) 앱으로 선다 — 창 없는 백그라운드 프로세스이고, 자기 창 모드에서만 패널을 띄운다.
// **엔진의 수명에 묶인다** — 연결이 끊기면 끝나고(`HostServer`), 붙기 전이라도 띄운 프로세스(엔진)가 끝나면 끝난다(예비 호스트를 띄우는 사이 엔진이
// 끝나면 연결을 기다리며 고아로 남았다 — 시험 프로세스의 표준 오류를 붙들어 `swift test` 가 끝나지 않았다).

public enum PreviewHost {
    public struct Config: Sendable {
        public var socket: String?
        public var activity = true

        public static func parse(_ args: [String]) -> Config {
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
    nonisolated(unsafe) private static var server: HostServer?
    nonisolated(unsafe) private static var parentWatch: DispatchSourceProcess?

    @MainActor
    public static func main(name: String, screens: [any PreviewScreen], layers: [LayerInfo] = [],
                            ia: IAInfo? = nil, frames: [DeviceFrameInfo]? = nil, tokensBuilt: BuiltTokens? = nil,
                            arguments: [String] = CommandLine.arguments, onTokensChanged: @escaping @MainActor () -> Void = {}) -> Never {
        Trace.mark("main 진입")
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
        Trace.mark("NSApplication 섬")
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
        Trace.mark("등록부 셈 끝(화면 \(screens.count))")
        let listener = try UnixSocket.listen(path: path)
        Trace.mark("소켓 들음")
        let s = HostServer(screens: screens, onTokensChanged: onTokensChanged)
        server = s
        // 받기는 막히는 호출이라 다른 스레드에서 — 받으면 그 스레드가 hello 를 보내고 읽기를 세운다
        Thread.detachNewThread {
            do {
                let fd = try UnixSocket.accept(listener)
                close(listener); unlink(path)
                try s.attach(Connection(fd: fd), hello: hello)
            } catch {
                FileHandle.standardError.write(Data("\(ProcessInfo.processInfo.processName): \(error)\n".utf8)); exit(1)
            }
        }
    }
}
#endif
