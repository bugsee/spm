/// View+Bugsee.swift
///
/// Created by Denis Sheikherev on 08.12.2021.
///
/// The MIT License (MIT)
///
/// Copyright (c) 2026 Bugsee
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.
///

// Usage:
/*
// Static protection (always hidden):
Text(landmark.description)
    .bugseeProtect()

// Dynamic protection (driven by @State or @Binding):
@State private var isHidden = false

Text(landmark.description)
    .bugseeProtect(isEnabled: $isHidden)
    .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isHidden = true
        }
    }

// If your View has offsets then you should call .bugseeProtect first:
CircleImage(image: landmark.image)
    .bugseeProtect()
    .offset(y: -130)
*/

#if canImport(SwiftUI)

import Foundation
import SwiftUI
import Bugsee

@available(iOS 13.0, *)
extension View {

    @available(*, deprecated, message: "Use bugseeProtect() or bugseeProtect(isEnabled:) instead. The closure variant will be removed in the future.")
    @ViewBuilder
    public func bugseeProtect(_ completion: @escaping (UIView) -> ()) -> some View {
        if #available(iOS 26.1, *) {
            bugseeOverlay261(BugseeProtectedOverlayUIView(completion: completion))
        } else {
            bugseeOverlay(BugseeProtectedOverlayUIView(completion: completion))
        }
    }

    @ViewBuilder
    public func bugseeProtect() -> some View {
        bugseeProtect(isEnabled: .constant(true))
    }

    @ViewBuilder
    public func bugseeProtect(isEnabled: Binding<Bool>) -> some View {
        if #available(iOS 26.1, *) {
            bugseeOverlay261(BugseeProtectedOverlayUIView(isProtected: isEnabled))
        } else {
            bugseeOverlay(BugseeProtectedOverlayUIView(isProtected: isEnabled))
        }
    }

    fileprivate func bugseeOverlay<SomeView>(_ view: SomeView) -> some View where SomeView: View {
        overlay(GeometryReader{ geometry in
            view.frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)
        })
    }

    @available(iOS 26.1, *)
    fileprivate func bugseeOverlay261<SomeView>(_ view: SomeView) -> some View where SomeView: View {
        overlay {
            GeometryReader { geometry in
                view.frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
            }
        }
    }
}

@available(iOS 13.0, *)
public struct BugseeProtectedOverlayUIView: UIViewRepresentable {

    let completion: ((UIView) -> ())?

    @Binding var isProtected: Bool

    public init(isProtected: Binding<Bool> = .constant(true),
                completion: ((UIView) -> Void)? = nil) {
        _isProtected = isProtected
        self.completion = completion
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        return view
    }

    public func updateUIView(
        _ uiView: UIView,
        context: Context
    ) {
        uiView.isUserInteractionEnabled = false
        uiView.backgroundColor = .clear

        if let completion = completion {
            completion(uiView)
        } else {
            uiView.bugseeProtectedView = isProtected
        }
    }
}

#endif
