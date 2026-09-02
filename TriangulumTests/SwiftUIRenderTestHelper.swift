//
//  SwiftUIRenderTestHelper.swift
//  TriangulumTests
//
//  The one shared SwiftUI render seam for every smoke suite (Cel components,
//  Almanac): hosts a SwiftUI view in a live UIWindow and forces layout so
//  SwiftUI evaluates `body` through the full render pipeline.
//
//  Note: this is intentionally a *smoke* seam. SwiftUI accessibility elements
//  are not reliably materialized synchronously through UIKit here
//  (`host.view.accessibilityElements` is empty outside a live assistive-tech
//  session), so render tests stay crash/layout coverage. Exact accessibility
//  copy is asserted through pure presentation helpers and the deterministic
//  XCUITest instead.
//

import SwiftUI
import UIKit

/// Wraps a SwiftUI view in a UIHostingController installed in a live UIWindow
/// and forces layout, causing SwiftUI to evaluate `body`.
///
/// Returns both the hosting controller and the owning `UIWindow`. The caller
/// MUST hold the returned window for the lifetime of its assertions: a
/// `UIWindow` created locally is only kept alive by `UIApplication`'s
/// undocumented key-window retention, which is unreliable (especially under
/// `UIScene`) and can let `host.view.window` become `nil` mid-test. Keeping a
/// strong reference guarantees the window survives until the test finishes.
@MainActor
func renderHost<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 320, height: 568)
) -> (host: UIHostingController<V>, window: UIWindow) {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return (host, window)
}
