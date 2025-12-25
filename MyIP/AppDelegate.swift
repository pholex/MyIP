//
//  AppDelegate.swift
//  IP Connect
//
//  Created by Paul Wong on 3/26/18.
//  Copyright © 2018 Mazookie, LLC. All rights reserved.
//

import Cocoa
import MapKit
import CoreLocation
import WidgetKit
import UserNotifications


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
    let timeInterval: Double = 60

    var timer: Timer!
    var preferenceController: NSWindowController!
    var aboutBoxController: NSWindowController!
    var aboutBoxView: AboutBoxViewController!
    var settings: Settings!

    var network = Network()
    var reachability: Reachability?
    var networkMonitor: NetworkMonitor?
    
    var mapImage: NSImage? = nil
    var latitude: CLLocationDegrees? = nil
    var longitude: CLLocationDegrees? = nil
    var locationManager:CLLocationManager!
    
    let mapView = MKMapView(frame: CGRect(x:0, y:0, width:320, height:180))


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        // load settings
        settings = Settings()
        processCommandLine()
        
        // 请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // 初始化网络监听器
        setupNetworkMonitor()
        
        // 检查初始网络状态，如果网络不可用则等待网络恢复
        if networkMonitor?.getCurrentNetworkStatus() == false {
            print("Network not available at startup, waiting for network...")
            statusItem.button?.image = settings.settings.useColorIcons
                ? NSImage(named:"StatusBarOrange") : NSImage(named:"StatusBarChecking")
        }
        
        if settings.settings.showLocation == true {
            // get location
            determineMyCurrentLocation()
            setMapImage()
        }

        // get ip as fast as you can
        network.onDirectIPUpdated = { [weak self] in
            self?.constructMenu()
        }
        network.getPublicIPWait { [weak self] in
            self?.update(false)
        }

        statusItem.button?.image = settings.settings.useColorIcons
            ? NSImage(named:"StatusBarGray") : NSImage(named:"StatusBarChecking")
        
        // Apply hide from menu bar setting
        statusItem.isVisible = !settings.settings.hideFromMenuBar
        
        startHost(at: 1)

        // Last things to do
        timer = Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: #selector(fireTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
    }

    func determineMyCurrentLocation() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // 检查当前权限状态 - 使用新的 API
        let authStatus: CLAuthorizationStatus
        if #available(macOS 11.0, *) {
            authStatus = locationManager.authorizationStatus
        } else {
            authStatus = CLLocationManager.authorizationStatus()
        }
        
        // macOS 的权限状态：notDetermined=0, denied=1, authorized=3
        if authStatus == .notDetermined {
            if #available(macOS 10.15, *) {
                locationManager.requestWhenInUseAuthorization()
            }
            return // 等待权限回调
        }
        
        if CLLocationManager.locationServicesEnabled() && authStatus == .authorized {
            locationManager.startUpdatingLocation()
        }
    }
    
    // 添加权限状态变化回调
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorized {
            locationManager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let userLocation:CLLocation = locations[0] as CLLocation
        
        // Call stopUpdatingLocation() to stop listening for location updates,
        // other wise this function will be called every time when user location changes or more.
        locationManager.stopUpdatingLocation()
        
        print("user latitude = \(userLocation.coordinate.latitude)")
        print("user longitude = \(userLocation.coordinate.longitude)")
        latitude = userLocation.coordinate.latitude
        longitude = userLocation.coordinate.longitude
        setMapImage()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
    {
        print("Error: \(error)")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        
        // Stop and invalidate timer to prevent memory leaks
        timer?.invalidate()
        timer = nil
        
        stopNotifier()
        networkMonitor?.stopMonitoring()
        
        // Clean up network callbacks to prevent memory leaks
        network.onDirectIPUpdated = nil
        
        // Clean up network monitor callbacks
        networkMonitor?.onNetworkAvailable = nil
        networkMonitor?.onNetworkUnavailable = nil
        
        // Clean up location manager to prevent memory leaks
        if locationManager != nil {
            locationManager.stopUpdatingLocation()
            locationManager.delegate = nil
        }
    }

    @objc func fireTimer(_ sender: Any?) {
        update(false)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func startHost(at index: Int) {
        setupReachability("8.8.8.8")
        startNotifier()
    }

    func setupNetworkMonitor() {
        networkMonitor = NetworkMonitor()
        
        networkMonitor?.onNetworkAvailable = { [weak self] in
            print("NetworkMonitor: Network became available, refreshing IP...")
            // 立即设置获取中状态并更新UI
            self?.network.setFetchingStatus()
            DispatchQueue.main.async {
                self?.updateUI()
            }
            // 确保网络真正可用后再获取IP
            self?.network.getPublicIPWait { [weak self] in
                DispatchQueue.main.async {
                    self?.update(false)
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
        
        networkMonitor?.onNetworkUnavailable = { [weak self] in
            print("NetworkMonitor: Network became unavailable")
            DispatchQueue.main.async {
                self?.updateUI()
            }
        }
        
        networkMonitor?.startMonitoring()
    }

    func setupReachability(_ hostName: String?) {
        let reach: Reachability?
        if let hostName = hostName {
            reach = Reachability(hostname: hostName)
        } else {
            reach = Reachability()
        }
        reachability = reach

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabilityChanged(_:)),
            name: .reachabilityChanged,
            object: reachability
        )
    }

    func startNotifier() {
        do {
            try reachability?.startNotifier()
        } catch {
            let alert = NSAlert()
            alert.informativeText = "Please try to restart MyIP, if issue persists please contact the developer."
            alert.messageText = "Unable to monitor network"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func stopNotifier() {
        reachability?.stopNotifier()
        NotificationCenter.default.removeObserver(self, name: .reachabilityChanged, object: nil)
        reachability = nil
    }

    @objc func reachabilityChanged(_ note: Notification) {
        guard let reachability = note.object as? Reachability else { return }
        print("Reachability changed, \(reachability.connection)...")
        self.reachability = reachability
        network.getPublicIPWait { [weak self] in
            self?.update(false)
            // 触发 Widget 刷新
            WidgetCenter.shared.reloadAllTimelines()
        }
        if settings.settings.useNotifications {
            notify()
        }
    }

    func notify() {
        var info: String

        if reachability?.connection == Reachability.Connection.none {
            info = "System has lost network connection."
        } else if network.externalIP == "N/A" {
            info = "System has no internet connection."
        } else {
            info = "System internet connection is now working."
        }

        let content = UNMutableNotificationContent()
        content.title = "MyIP"
        content.body = info
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func update(_ force: Bool) {
        let connectionStatus = reachability?.connection.description ?? "Unknown"
        print("Updating (force == \(force)), \(connectionStatus)...")
        
        if force {
            if settings.settings.showLocation == true {
                locationManager.startUpdatingLocation()
            }
            network.getPublicIPWait { [weak self] in
                self?.updateUI()
            }
        } else {
            if settings.settings.showLocation == true && mapImage == nil {
                locationManager.startUpdatingLocation()
            }
            network.getPublicIPWait { [weak self] in
                guard let self = self else { return }
                if self.network.getHasIpChanged() {
                    self.network.setHasIpChanged(false)
                }
                self.updateUI()
            }
        }
    }
    
    func updateUI() {
        // 优先使用NetworkMonitor的判断
        if network.externalIP != "N/A" && network.externalIP != "获取中..." {
            // 有真实IP时，根据连接类型显示对应图标
            if reachability?.connection == Reachability.Connection.cellular {
                statusItem.button?.image = settings.settings.useColorIcons
                    ? NSImage(named:"StatusBarBlue") : NSImage(named:"StatusBarCell")
            } else {
                // 默认显示WiFi状态（包括NetworkMonitor检测到的网络可用情况）
                statusItem.button?.image = settings.settings.useColorIcons
                    ? NSImage(named:"StatusBarGreen") : NSImage(named:"StatusBarConnected")
            }
        } else if reachability?.connection == Reachability.Connection.none {
            // 明确无网络连接
            statusItem.button?.image = settings.settings.useColorIcons ?
                NSImage(named:"StatusBarRed") : NSImage(named:"StatusBarNotConnected")
        } else {
            // 获取中或其他中间状态
            statusItem.button?.image = settings.settings.useColorIcons
                ? NSImage(named:"StatusBarOrange") : NSImage(named:"StatusBarWarning")
        }
        if settings.settings.showExternalIP == true {
            statusItem.button?.attributedTitle = NSAttributedString(
                string:  network.externalIP,
                attributes: [NSAttributedString.Key.font:  NSFont(name: "Helvetica Neue", size: 12)!]
            )
        } else {
            statusItem.button?.attributedTitle = NSAttributedString()
        }
        
        constructMenu()
    }

    func constructMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let myAttribute = [NSAttributedString.Key.font: NSFont(name: "Andale Mono", size: 14.0)!]

        let hostnameMenuItem = NSMenuItem(title: "Hostname", action: #selector(AppDelegate.doNothing(_:)), keyEquivalent: "")
        hostnameMenuItem.isEnabled = false
        menu.addItem(hostnameMenuItem)

        let nameMenuItem = NSMenuItem(title: "", action: #selector(AppDelegate.copyTitle(_:)), keyEquivalent: "")
        nameMenuItem.indentationLevel = 1
        nameMenuItem.attributedTitle = NSAttributedString(string: Host.current().localizedName ?? "", attributes: myAttribute)
        menu.addItem(nameMenuItem)
        menu.addItem(NSMenuItem.separator())

        // 检测是否使用代理
        let isUsingProxy = network.directIP != "N/A" && network.directIP != network.externalIP
        
        let externalMenuItem = NSMenuItem(title: "", action: #selector(AppDelegate.doNothing(_:)), keyEquivalent: "")
        externalMenuItem.isEnabled = false
        if isUsingProxy {
            let attrStr = NSMutableAttributedString(string: "External  ")
            let proxyTextAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.controlTextColor]
            if let shieldImage = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                let coloredImage = shieldImage.withSymbolConfiguration(config)
                let attachment = NSTextAttachment()
                attachment.image = coloredImage?.tinted(with: .systemBlue)
                attrStr.append(NSAttributedString(attachment: attachment))
                
                // 添加 4 点间距，与 Widget 的 HStack(spacing: 4) 保持一致
                let spacingAttrs: [NSAttributedString.Key: Any] = [.kern: 4.0]
                attrStr.append(NSAttributedString(string: " ", attributes: spacingAttrs))
                attrStr.append(NSAttributedString(string: "PROXY", attributes: proxyTextAttrs))
            } else {
                attrStr.append(NSAttributedString(string: "PROXY", attributes: proxyTextAttrs))
            }
            externalMenuItem.attributedTitle = attrStr
        } else {
            externalMenuItem.title = "External"
        }
        menu.addItem(externalMenuItem)

        let externalIPMenuItem = NSMenuItem(title: "", action: #selector(AppDelegate.copyIp(_:)), keyEquivalent: "")
        externalIPMenuItem.indentationLevel = 1
        externalIPMenuItem.attributedTitle = NSAttributedString(string: network.externalIP, attributes: myAttribute)
        menu.addItem(externalIPMenuItem)
        
        // 只在直连 IP 与外部 IP 不同时才显示直连 IP（说明真正使用了代理）
        if isUsingProxy {
            let directLabel = NSMenuItem(title: "Direct", action: #selector(AppDelegate.doNothing(_:)), keyEquivalent: "")
            directLabel.isEnabled = false
            menu.addItem(directLabel)
            
            let directIPMenuItem = NSMenuItem(title: "", action: #selector(AppDelegate.copyTitle(_:)), keyEquivalent: "")
            directIPMenuItem.indentationLevel = 1
            directIPMenuItem.attributedTitle = NSAttributedString(string: network.directIP, attributes: myAttribute)
            menu.addItem(directIPMenuItem)
        }
        
        // 显示物理位置（GPS/Wi-Fi 定位）
        if settings.settings.showLocation == true && mapImage != nil {
            let locationLabel = NSMenuItem(title: "Physical Location", action: #selector(AppDelegate.doNothing(_:)), keyEquivalent: "")
            locationLabel.isEnabled = false
            menu.addItem(locationLabel)
            
            let locationMenuItem = NSMenuItem(title: "", action: #selector(AppDelegate.openMaps(_:)), keyEquivalent: "")
            locationMenuItem.indentationLevel = 1
            locationMenuItem.image = mapImage
            menu.addItem(locationMenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())

        let internalMenuItem = NSMenuItem(title: "Internal", action: #selector(AppDelegate.doNothing(_:)), keyEquivalent: "")
        internalMenuItem.isEnabled = false
        menu.addItem(internalMenuItem)

        for interface in Network().getIFAddresses(false) {
            var internalIP = NSMenuItem(title: "", action: #selector(AppDelegate.doNothing(_:)), keyEquivalent: "")
            internalIP.indentationLevel = 1
            
            // 构建显示文本：类型 (接口名) - 应用名:
            var displayText = "\(interface["type"]!) (\(interface["name"]!))"
            if let app = interface["app"], !app.isEmpty {
                displayText += " - \(app)"
            }
            displayText += ":"
            
            internalIP.attributedTitle = NSAttributedString(
                string: displayText,
                attributes: myAttribute
            )
            menu.addItem(internalIP)
            internalIP = NSMenuItem(title: "", action: #selector(AppDelegate.copyTitle(_:)), keyEquivalent: "")
            internalIP.indentationLevel = 3
            internalIP.attributedTitle = NSAttributedString(
                string: "\(interface["ip_address"]!)",
                attributes: myAttribute
            )
            menu.addItem(internalIP)

            // 只在有 MAC 地址时才显示
            if let mac = interface["mac_address"], !mac.isEmpty {
                internalIP = NSMenuItem(title: "", action: #selector(AppDelegate.copyTitle(_:)), keyEquivalent: "")
                internalIP.indentationLevel = 3
                internalIP.attributedTitle = NSAttributedString(
                    string: mac,
                    attributes: myAttribute
                )
                menu.addItem(internalIP)
            }
        }

        menu.addItem(NSMenuItem.separator())
        var showmenu = NSMenuItem(title: "Show External IP", action: #selector(AppDelegate.showExternalIP(_:)), keyEquivalent: "s")
        if settings.settings.showExternalIP == true {
            showmenu.state = NSControl.StateValue.on
        } else {
            showmenu.state = NSControl.StateValue.off
        }
        menu.addItem(showmenu)
        showmenu = NSMenuItem(title: "Use color icons", action: #selector(AppDelegate.useColorIcons(_:)), keyEquivalent: "c")
        if settings.settings.useColorIcons == true {
            showmenu.state = NSControl.StateValue.on
        } else {
            showmenu.state = NSControl.StateValue.off
        }
        menu.addItem(showmenu)
        showmenu = NSMenuItem(title: "Use notifications ", action: #selector(AppDelegate.useNotifications(_:)), keyEquivalent: "n")
        if settings.settings.useNotifications == true {
            showmenu.state = NSControl.StateValue.on
        } else {
            showmenu.state = NSControl.StateValue.off
        }
        menu.addItem(showmenu)
        showmenu = NSMenuItem(title: "Launch at login", action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: "l")
        showmenu.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(showmenu)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About...", action: #selector(AppDelegate.openAbout(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(AppDelegate.refresh(_:)), keyEquivalent: "r"))

        let historyMenu = NSMenu()
        historyMenu.autoenablesItems = false
        historyMenu.addItem(NSMenuItem(title: "Show", action: #selector(AppDelegate.showHistory(_:)), keyEquivalent: ""))
        historyMenu.addItem(NSMenuItem.separator())
        historyMenu.addItem(NSMenuItem(title: "Clear", action: #selector(AppDelegate.clearHistory(_:)), keyEquivalent: ""))

        let historyItem = NSMenuItem()
        historyItem.title = "History"
        menu.addItem(historyItem)
        menu.setSubmenu(historyMenu, for: historyItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Network Preferences...", action: #selector(AppDelegate.openNetworkPreferences(_:)), keyEquivalent: ""))

        showmenu = NSMenuItem(title: "Hide from Menu Bar", action: #selector(AppDelegate.hideFromMenuBar(_:)), keyEquivalent: "h")
        if settings.settings.hideFromMenuBar == true {
            showmenu.state = NSControl.StateValue.on
        } else {
            showmenu.state = NSControl.StateValue.off
        }
        menu.addItem(showmenu)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(AppDelegate.quit(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func setMapImage() {
        let pin = NSImage(named:"StatusBarOrange")
        print("Getting map image")
        
        if (latitude != nil) && (longitude != nil) {
            
            let current_location = CLLocationCoordinate2DMake(latitude!, longitude!)
            var mapRegion = MKCoordinateRegion()
            //var mapView = MKMapView(frame: CGRect(x:0, y:0, width:320, height:180))
            
            // Set size
            let mapRegionSpan = 0.2
            mapRegion.center = current_location
            mapRegion.span.latitudeDelta = mapRegionSpan
            mapRegion.span.longitudeDelta = mapRegionSpan
            mapView.setRegion(mapRegion, animated: true)

            // Clear old annotations to prevent memory leak
            mapView.removeAnnotations(mapView.annotations)
            
            // Create a map annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = current_location
            annotation.title = "Here"
            annotation.subtitle = "Your current Public IP location"
            mapView.addAnnotation(annotation)

            let options = MKMapSnapshotter.Options()
            options.region = mapView.region;
            options.size = mapView.frame.size;
            let mapSnapshotter = MKMapSnapshotter(options: options)

            mapSnapshotter.start { [weak self] (snapshot, error) -> Void in
                guard let self = self else { return }
                if error != nil {
                    self.mapImage = nil
                    print("Unable to create a map snapshot.")
                } else if let snapshot = snapshot {
                    self.mapImage = nil
                    self.mapImage = snapshot.image
                    self.mapImage!.lockFocus()
                    let visibleRect = CGRect(origin: CGPoint.zero, size: snapshot.image.size)
                    for annotation in self.mapView.annotations {
                        var point = snapshot.point(for: annotation.coordinate)
                        if visibleRect.contains(point) {
                            if let pin = pin {
                                point.x = point.x - (pin.size.width / 2)
                                point.y = point.y - (pin.size.height / 2)
                                pin.draw(at: point, from: CGRect(origin: CGPoint.zero, size: snapshot.image.size), operation: .sourceAtop, fraction: 1.0)
                            }
                        }
                    }
                    self.mapImage!.unlockFocus()
                    self.constructMenu()
                }
            }
            
        } else {
            print("Unable to get map image.")
        }
    }


    @objc func refresh(_ sender: Any?) {
        if settings.settings.showLocation == true {
            // 检查上次位置更新是否超过60秒
            let shouldUpdateLocation = locationManager.location?.timestamp.timeIntervalSinceNow ?? -61 < -60
            if shouldUpdateLocation {
                locationManager.startUpdatingLocation()
            }
        }
        network.getPublicIPWait { [weak self] in
            self?.updateUI()
            // 手动刷新时也要触发 Widget 更新
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @objc func showHistory(_ sender: Any?) {
        History.open()
    }

    @objc func clearHistory(_ sender: Any?) {
        History.reset()
        network.priorIP = "None"
        update(true)
    }

    @objc func openNetworkPreferences(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Network.prefPane"))
    }

    func matches(for regex: String, in text: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: text,
                                        range: NSRange(text.startIndex..., in: text))
            return results.map {
                String(text[Range($0.range, in: text)!])
            }
        } catch let error {
            print("Invalid regex: \(error.localizedDescription)")
            return []
        }
    }

    @objc func copyIp(_ sender: Any?) {
        let mi = sender as! NSMenuItem
        let matched = matches(for: "\\b[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}", in: mi.title)
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        pasteboard.setString(matched[0], forType: NSPasteboard.PasteboardType.string)
        print("Copying \(matched[0]) to the clipboard...")
    }

    @objc func copyName(_ sender: Any?) {
        let mi = sender as! NSMenuItem
        let fullArr : [String] = mi.title.components(separatedBy: ": ")
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        pasteboard.setString(fullArr[1], forType: NSPasteboard.PasteboardType.string)
        print("Copying \(fullArr[1]) to the clipboard...")
    }

    @objc func copyTitle(_ sender: Any?) {
        let mi = sender as! NSMenuItem
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        pasteboard.setString(mi.title, forType: NSPasteboard.PasteboardType.string)
        print("Copying \(mi.title) to the clipboard...")
    }

    @objc func openMaps(_ sender: Any?) {
        _ = sender as! NSMenuItem
        let coordinate = CLLocationCoordinate2DMake(latitude ?? 45.5051, longitude ?? -0122.6750)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate, addressDictionary:nil))
        mapItem.name = "Your Physical Location"
        mapItem.openInMaps(launchOptions: nil)
        print("Opening maps at (\(latitude ?? 0),\(longitude ?? 0))...")
    }

    @objc func doNothing(_ sender: Any?) {
    }

    @objc func showExternalIP(_ sender: Any?) {
        settings.settings.showExternalIP = !settings.settings.showExternalIP
        settings.archive()
        update(true)
    }

    @objc func useNotifications(_ sender: Any?) {
        settings.settings.useNotifications = !settings.settings.useNotifications
        settings.archive()
        update(true)
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        LaunchAtLogin.toggle()
        constructMenu()
    }

    @objc func useColorIcons(_ sender: Any?) {
        settings.settings.useColorIcons = !settings.settings.useColorIcons
        settings.archive()
        update(true)
    }

    @objc func hideFromMenuBar(_ sender: Any?) {
        settings.settings.hideFromMenuBar = !settings.settings.hideFromMenuBar
        settings.archive()
        if settings.settings.hideFromMenuBar {
            statusItem.isVisible = false
        } else {
            statusItem.isVisible = true
        }
        constructMenu()
    }

    @objc func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    @IBAction func openAbout(_ sender: Any?) {
        if aboutBoxController == nil {
            let mainStoryboard = NSStoryboard.init(name: "AboutBox", bundle: nil)
            aboutBoxController = (mainStoryboard.instantiateController(
                withIdentifier: "About Box") as! NSWindowController)
            aboutBoxView = (mainStoryboard.instantiateController(
                withIdentifier: "AboutBox Controller"
                ) as! AboutBoxViewController)
            aboutBoxController.contentViewController = aboutBoxView
            aboutBoxView.setMacId(newMacId: "id1368972441")
        }
        aboutBoxController.showWindow(self)
        aboutBoxController.window?.makeKeyAndOrderFront(self)
        aboutBoxView.forceHelp(force: false)
        NSApp.activate(ignoringOtherApps: true)
    }

    func processCommandLine() {
        let arguments = ProcessInfo.processInfo.arguments
        // reset takes takes priority
        for i in 0..<arguments.count {
            if (arguments[i] == "-R") {
                settings.reset()
                print("Reset configuration.")
            }
        }
        // now handle the rest
        for i in 0..<arguments.count {
            switch arguments[i] {
                case "-L:1":
                    settings.settings.showLocation = true
                    settings.archive()
                    print("Enable location services.")
                case "-L:0":
                    settings.settings.showLocation = false
                    settings.archive()
                    print("Disable location services.")
                case "-R":
                    print("Reset configuration, already handled.")
                default:
                    print("Unhandled argument: \(arguments[i])")
            }
        }
    }
}


// MARK: - NSImage Extension
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
