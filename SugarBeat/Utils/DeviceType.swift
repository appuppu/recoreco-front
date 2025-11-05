import UIKit
import SwiftUI

enum DeviceType {
    case iPhone
    case iPad

    static var current: DeviceType {
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }

    static var isIPad: Bool {
        current == .iPad
    }

    static var isIPhone: Bool {
        current == .iPhone
    }
}

struct ScreenSize {
    static var width: CGFloat {
        UIScreen.main.bounds.width
    }

    static var height: CGFloat {
        UIScreen.main.bounds.height
    }

    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // Dynamic button width based on screen size
    static var buttonWidth: CGFloat {
        if isIPad {
            return min(width * 0.5, 400) // Max 400pt on iPad
        } else {
            return width * 0.8 // 80% of screen width on iPhone
        }
    }

    // Dynamic horizontal padding
    static var horizontalPadding: CGFloat {
        if isIPad {
            return 80
        } else {
            return 40
        }
    }

    // Dynamic font sizes
    static func fontSize(_ baseSize: CGFloat) -> CGFloat {
        if isIPad {
            return baseSize * 1.2
        } else {
            return baseSize
        }
    }
}

extension View {
    func iPadAdaptive<Content: View>(
        iPhone: () -> Content,
        iPad: () -> Content
    ) -> some View {
        Group {
            if DeviceType.isIPad {
                iPad()
            } else {
                iPhone()
            }
        }
    }
}
