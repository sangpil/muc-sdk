#if os(macOS)
import AppKit
import Observation
import SwiftUI

// 호스트 자기 창 — Xcode Previews 방식. 엔진은 창 자리만 안내하고(`window{x,y}`) 호스트가 진짜 SwiftUI 뷰를 제 창에 띄운다.
// 그러면 스크롤 · 탭 · 애니메이션 · 호버 · 유리가 앱과 같다(프로세스 안 직접 뷰). 비용은 창 둘의 겹침 · 따라 움직이기.
//
// 창은 **활성화하지 않는 패널**(`nonactivatingPanel`)이다 — 눌러도 호스트 앱이 앞으로 오지 않아 엔진의 메뉴 · 단축키가 그대로 선다.
// 테두리 없는 패널은 기본으로 key 가 못 된다 — 그러면 첫 클릭이 화면 안 손(onTapGesture)에 닿지 않는다.
// 그래서 `canBecomeKey` 만 연다(Spotlight 꼴 — 앱을 활성화하지 않고 키 입력 · 클릭을 받는다).
// 같은 꼴이 기준선(창 안 직접 뷰)에도 쓰인다 — 한 프로세스 안에서 값 → 커밋을 재는 자리.

@MainActor
package final class WindowPresenter {
    @Observable final class Box { var content = AnyView(EmptyView()) }
    struct BoxView: View {
        let box: Box
        var body: some View { box.content }
    }

    final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    let box = Box()
    package let window: NSPanel
    package let hosting: NSView
    /// 화면의 크기(pt) — 창은 그 가운데 보이는 부분(`clip`)만일 수 있다
    package private(set) var size: CGSize
    private var clip: CGRect?

    package init(size: CGSize, origin: CGPoint) {
        self.size = size
        let p = KeyablePanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.hasShadow = false
        p.isOpaque = true
        p.backgroundColor = .white
        // 창의 몸은 틀(자르는 뷰) — 화면 뷰는 제 크기 그대로 그 안에 놓이고, 창이 보이는 부분만일 때 틀이 자른다
        let frame = NSView(frame: CGRect(origin: .zero, size: size))
        let h = NSHostingView(rootView: BoxView(box: box))
        h.frame = CGRect(origin: .zero, size: size)
        frame.addSubview(h)
        p.contentView = frame
        window = p; hosting = h
    }

    package func update(_ view: AnyView) { box.content = view }
    /// 화면 크기를 바꾼다(엔진이 미리보기 크기를 바꿨다 · 창 요청의 `w` · `h`).
    package func resize(to size: CGSize) {
        guard self.size != size else { return }
        self.size = size
        clip = clip?.intersection(CGRect(origin: .zero, size: size))   // 옛 보이는 부분이 새 크기 밖으로 나가지 않게(크기만 바뀐 render 한 틱)
        layout()
    }
    /// 보이는 부분(화면 안의 자리 · 위-왼쪽 원점 · nil = 전부) — 창은 그만큼만 서고 화면은 제 자리에 그대로.
    package func clip(to rect: CGRect?) {
        let r = rect.map { $0.intersection(CGRect(origin: .zero, size: size)) }
        guard r != clip else { return }
        clip = r
        layout()
    }
    /// 보이는 부분 — 화면 좌표의 창 틀(아래-왼쪽 원점)과 그 안의 화면 뷰 자리.
    private var visible: CGRect { clip ?? CGRect(origin: .zero, size: size) }
    private func layout() {
        let v = visible
        window.setContentSize(v.size)
        // 화면 뷰의 왼쪽 아래 = 틀의 왼쪽 아래에서 (−보이는 부분의 x, −화면 아래 끝에서 보이는 부분의 아래 끝까지)
        hosting.frame = CGRect(x: -v.minX, y: -(size.height - v.maxY), width: size.width, height: size.height)
    }
    /// 세운다 — `origin` = 화면 전체의 왼쪽 아래(화면 좌표) · 창은 보이는 부분 자리로. `above` = 엔진 창 번호면 그 창 바로 위 보통 층
    /// (엔진이 뒤로 가면 다른 앱 창 밑으로) · nil 이면 떠 있는 층(측정 하니스).
    package func show(at origin: CGPoint, above: Int? = nil) {
        let v = visible
        window.setFrameOrigin(CGPoint(x: origin.x + v.minX, y: origin.y + (size.height - v.maxY)))
        if let above {
            window.level = .normal
            window.order(.above, relativeTo: above)
        } else {
            window.level = .floating
            window.orderFrontRegardless()
        }
    }
    package func hide() { window.orderOut(nil) }
}

/// 다음 커밋 뒤 — 메인 런루프의 `beforeWaiting` 에 순서 맨 끝(CA 커밋 관찰자 뒤) 한 번짜리 관찰자를 건다.
/// 값을 바꾼 그 바퀴가 끝나며 SwiftUI 갱신 → CA 커밋이 돈 뒤에 불린다 — 「값 → 렌더 서버로 넘김」 시각(유리 위 표시는 그 뒤 vsync).
public enum HostCommit {
    @MainActor public static func next(_ body: @escaping @MainActor () -> Void) {
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in
            MainActor.assumeIsolated { body() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
    }
}
#endif
