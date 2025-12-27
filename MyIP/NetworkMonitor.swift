//
//  NetworkMonitor.swift
//  MyIP
//
//  Created by AI Assistant on 2025/12/25.
//

import Foundation
import SystemConfiguration

class NetworkMonitor {
    private var reachability: SCNetworkReachability?
    private var isMonitoring = false
    
    var onNetworkAvailable: (() -> Void)?
    var onNetworkUnavailable: (() -> Void)?
    
    init() {
        setupReachability()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func setupReachability() {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        reachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }
    }
    
    func startMonitoring() {
        guard let reachability = reachability, !isMonitoring else { return }
        
        var context = SCNetworkReachabilityContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: SCNetworkReachabilityCallBack = { (reachability, flags, info) in
            guard let info = info else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.handleNetworkChange(flags: flags)
        }
        
        if SCNetworkReachabilitySetCallback(reachability, callback, &context) {
            if SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                isMonitoring = true
                print("NetworkMonitor: Started monitoring network changes")
            }
        }
    }
    
    func stopMonitoring() {
        guard let reachability = reachability, isMonitoring else { return }
        
        SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        SCNetworkReachabilitySetCallback(reachability, nil, nil)
        isMonitoring = false
        print("NetworkMonitor: Stopped monitoring network changes")
    }
    
    private func handleNetworkChange(flags: SCNetworkReachabilityFlags) {
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        let isNetworkAvailable = isReachable && !needsConnection
        
        print("NetworkMonitor: Network change detected - Available: \(isNetworkAvailable), Flags: \(flags)")
        
        if isNetworkAvailable {
            // 网络可用时，先立即尝试一次
            DispatchQueue.main.async {
                self.onNetworkAvailable?()
            }
            
            // 延迟1秒后测试真实连通性
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.testInternetConnectivity { isConnected in
                    if isConnected {
                        print("NetworkMonitor: Internet connectivity confirmed")
                        self.onNetworkAvailable?()
                    } else {
                        print("NetworkMonitor: Network reachable but no internet access")
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.onNetworkUnavailable?()
            }
        }
    }
    
    func getCurrentNetworkStatus() -> Bool {
        guard let reachability = reachability else { return false }
        
        var flags: SCNetworkReachabilityFlags = []
        if SCNetworkReachabilityGetFlags(reachability, &flags) {
            let isReachable = flags.contains(.reachable)
            let needsConnection = flags.contains(.connectionRequired)
            return isReachable && !needsConnection
        }
        return false
    }
    
    // 测试网络连通性的辅助方法
    func testInternetConnectivity(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://1.1.1.1/cdn-cgi/trace") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            let isConnected = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(isConnected)
            }
        }.resume()
    }
}
