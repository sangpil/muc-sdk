/// 폼팩터 — 프로젝트가 겨냥하는 기기의 낱말 **한 벌**. 매니페스트 `muc.json` 의 `platforms` 와
/// IA 의 플랫폼 칸(허브 · 마디의 `platforms` — 프로젝트의 생성 상수)이 같은 글자를 쓴다. 차례는 좁은 것에서 넓은 것으로(표 · 메뉴의 차례).
public enum FormFactor: String, CaseIterable, Sendable, Hashable {
    case iphone
    case ipad
    case mac
}
