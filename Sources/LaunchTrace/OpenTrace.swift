import Foundation

// 창 열기 실측 훅(엔진 SDK) — `MUC_OPEN_TRACE=1` 일 때만 돈다(DEBUG · 그 밖엔 한 줄도 재지 않는다 · 출시 빌드에서 부르는 자리는 몸이 빈 함수다).
// **창 하나가 서기까지**를 재는 자다 — 프로젝트의 화면 코드(그리는 횟수 · 첫 body)와 엔진의 도구(창 세우기 · 모델 만들기)가 같은 눈금에 표지를 남긴다.
//   ① 시각의 기준이 프로세스 **시작**이다(커널의 p_starttime) — dyld · 런타임 초기화까지 앞에 든다.
//   ② `mark` : 그 지점까지 흐른 시각 + 직전 표지로부터의 간격. 구간 표가 이 두 수로 선다.
//   ③ `span` : 한 일의 소요(안 파일 읽기 · 픽스처 디코드 · Mirror …).
//   ④ `arm`  : 워치독(메인 정지) + **첫 유휴** 표지. 메인 런루프가 처음 쉬러 가는 순간이 곧 첫 프레임이 선 뒤다.
// 출력은 표준 오류 한 줄씩(`[open] …`) · 계측 자체가 메인을 세우지 않게 문자열은 자동 클로저다. Foundation 만(sysctl · CFRunLoop 는 Darwin).
public enum OpenTrace {
    #if DEBUG
    public static let on = ProcessInfo.processInfo.environment["MUC_OPEN_TRACE"] == "1"
    nonisolated(unsafe) private static var lastMark: UInt64 = 0
    nonisolated(unsafe) private static var stallMax: Double = 0
    nonisolated(unsafe) private static var armed = false
    nonisolated(unsafe) private static var sawFirstIdle = false
    nonisolated(unsafe) private static var once = Set<String>()
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    /// 프로세스가 뜬 순간을 uptime 눈금으로 — 커널의 p_starttime(벽시계)을 지금의 uptime 에 옮겨 앉힌다.
    private static let launchUptime: UInt64 = {
        let nowUp = DispatchTime.now().uptimeNanoseconds
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nowUp }
        let st = info.kp_proc.p_un.__p_starttime
        let startWall = Double(st.tv_sec) + Double(st.tv_usec) / 1e6
        let ago = Date().timeIntervalSince1970 - startWall
        guard ago > 0, ago < 600 else { return nowUp }
        let back = UInt64(ago * 1e9)
        return back < nowUp ? nowUp &- back : nowUp
    }()
    /// 프로세스 시작부터 흐른 ms.
    private static var since: Double { Double(DispatchTime.now().uptimeNanoseconds &- launchUptime) / 1e6 }
    private static func say(_ s: String) { FileHandle.standardError.write(Data((String(format: "%8.1f ", since) + s + "\n").utf8)) }
    #endif

    /// 표지 하나 — 「프로세스 시작부터 N ms · 직전 표지로부터 +M ms」.
    public static func mark(_ what: @autoclosure () -> String) {
        #if DEBUG
        guard on else { return }
        arm()
        let now = DispatchTime.now().uptimeNanoseconds
        let gap = lastMark == 0 ? Double(now &- launchUptime) / 1e6 : Double(now &- lastMark) / 1e6
        lastMark = now
        say(String(format: "[open] %@  (+%.1f ms)", what(), gap))
        #endif
    }

    /// 표지 하나 — **처음 한 번만**(뷰 body 는 여러 번 돈다 · 첫 body 만이 창 열기 몫이다).
    public static func first(_ key: String, _ what: @autoclosure () -> String) {
        #if DEBUG
        guard on else { return }
        arm()
        counts[key, default: 0] += 1
        guard !once.contains(key) else { return }
        once.insert(key)
        mark(what())
        #endif
    }

    /// 몇 번 돌았나 — body 마다 한 줄을 찍으면 그 찍기가 곧 정지가 되니 **세기만** 하고 첫 유휴에 표로 낸다.
    public static func count(_ key: String) {
        #if DEBUG
        guard on else { return }
        arm()
        counts[key, default: 0] += 1
        #endif
    }

    /// 한 일의 소요 — 표지와 같은 줄에 ms 를 얹는다.
    public static func span<T>(_ what: @autoclosure () -> String, _ body: () throws -> T) rethrows -> T {
        #if DEBUG
        guard on else { return try body() }
        arm()
        let t0 = DispatchTime.now().uptimeNanoseconds
        let r = try body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        lastMark = DispatchTime.now().uptimeNanoseconds
        say(String(format: "[open] · %@ %.1f ms", what(), ms))
        return r
        #else
        return try body()
        #endif
    }

    /// 한 번만 선다 — 메인 정지 감시 + 첫 유휴 표지. 어느 훅이든 처음 불릴 때 **스스로** 건다(실행물의 진입점에 한 줄도 두지 않는다).
    public static func arm() {
        #if DEBUG
        guard on, !armed else { return }
        armed = true
        say("[open] 계측 시작(시각은 언제나 **프로세스 시작** 기준 — 워치독은 이 줄부터 본다)")
        lastMark = DispatchTime.now().uptimeNanoseconds
        // 첫 유휴 — 메인 런루프가 처음 쉬러 갈 때. 창이 그려지고 메인이 놓인 순간이다.
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, _ in
            guard !sawFirstIdle else { return }
            sawFirstIdle = true
            let now = DispatchTime.now().uptimeNanoseconds
            say(String(format: "[open] 첫 유휴(첫 프레임 뒤 · 메인이 놓였다)  (+%.1f ms)", Double(now &- lastMark) / 1e6))
            lastMark = now
            if !counts.isEmpty { say("[open] 첫 프레임까지 body 횟수 — " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · ")) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        // 워치독 — 5 ms 간격으로 메인 큐에 탐침. 런루프가 아직 안 돌면 탐침이 쌓였다가 한꺼번에 나오니
        // 첫 줄의 큰 값은 「런루프 시작 전 메인이 한 일」로 읽는다.
        let t = Thread {
            while true {
                let probe = DispatchTime.now().uptimeNanoseconds
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    let d = Double(DispatchTime.now().uptimeNanoseconds - probe) / 1e6
                    if d > 10 || d > stallMax + 1 { say(String(format: "[open] 메인 정지 %.1f ms%@", d, d > stallMax ? " (최대)" : "")) }
                    stallMax = max(stallMax, d)
                    sem.signal()
                }
                sem.wait()
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        t.qualityOfService = .userInteractive
        t.name = "open-watchdog"
        t.start()
        #endif
    }
}
