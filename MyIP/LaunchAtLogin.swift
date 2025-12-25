//
//  LaunchAtLogin.swift
//  IP Connect
//

import Foundation
import ServiceManagement

struct LaunchAtLogin {
    
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return UserDefaults.standard.bool(forKey: "launchAtLogin")
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                }
            } else {
                // macOS 12 及以下使用旧 API
                let bundleId = Bundle.main.bundleIdentifier!
                SMLoginItemSetEnabled(bundleId as CFString, newValue)
                UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            }
        }
    }
    
    static func toggle() {
        isEnabled = !isEnabled
    }
}
