//
//  MZNESettings.swift
//  NextEvent
//
//  Created by Paul Wong on 2/4/18.
//  Copyright © 2018 Mazookie, LLC. All rights reserved.
//

import Foundation

class Settings: NSObject {

    struct Settings: Codable {
        // persistant
        var showLocation: Bool = true
        var showExternalIP: Bool = false
        var useNotifications: Bool = false
        var useColorIcons: Bool = false
        var hideFromMenuBar: Bool = false
    }

    var settings: Settings = Settings()
    var needsDisplay: Bool = false

    override init() {
        super.init()
        unarchive()
    }

    func unarchive() {
        do {
            let readData = try Data(contentsOf: archivePath())
            self.settings = try JSONDecoder().decode(Settings.self, from: readData)
        } catch {
            reset()
        }
        needsDisplay = true
    }

    func archive() {
        do {
            let jsonData = try JSONEncoder().encode(self.settings)
            try jsonData.write(to: archivePath())
            needsDisplay = true
        } catch {
            print("Failed to archive settings: \(error)")
        }
    }

    func archivePath() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("MyIP", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("settings.json")
    }

    func reset() {
        settings.showLocation = true
        settings.showExternalIP = false
        settings.useNotifications = false
        settings.useColorIcons = false
        settings.hideFromMenuBar = false
        archive()
    }
}

