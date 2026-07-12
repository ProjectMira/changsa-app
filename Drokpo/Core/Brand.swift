import SwiftUI

/// Drokpo's brand palette: blue (`AccentColor`, the app's tint) is primary —
/// buttons, links, chat bubbles, selected tabs. Red (`brandRed`) is reserved
/// for like/love actions — hearts, the like button, the LIKE stamp — and is
/// also the brand ground behind the blue handshake on the app icon and the
/// sign-in logo (see ci/make_brand_assets.py).
extension Color {
    static let brandRed = Color("BrandRed")
}

/// Mirrors Apple's own `ShapeStyle where Self == Color` extensions (e.g.
/// `.pink`, `.red`) so `.brandRed` resolves via leading-dot syntax in
/// `ShapeStyle`-typed contexts like `.foregroundStyle(.brandRed)`, not just
/// `Color`-typed ones like `.tint(.brandRed)`.
extension ShapeStyle where Self == Color {
    static var brandRed: Color { Color.brandRed }
}
