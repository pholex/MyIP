//
//  Network.swift
//  IP Connect
//
//  Created by Paul Wong on 3/26/18.
//  Copyright © 2018 Mazookie, LLC. All rights reserved.
//

import Foundation
import Cocoa
import SystemConfiguration


class Network {

    var externalIP: String = "N/A"
    var directIP: String = "N/A"
    var priorIP: String = "None"

    var hasIpChanged: Bool = true
    
    // 设置获取中状态
    func setFetchingStatus() {
        externalIP = "获取中..."
    }

    func getHasIpChanged() -> Bool {
        return hasIpChanged
    }

    func setHasIpChanged(_ value: Bool) {
        hasIpChanged = value
    }

    func getExternalIP() -> String {
        getPublicIPNoWait()
        return externalIP
    }

    func parseIP(_ message:String) -> String {
        var newIP: String = ""
        
        // 检查是否是 Cloudflare trace 格式 (ip=x.x.x.x)
        if message.contains("ip=") {
            let lines = message.components(separatedBy: "\n")
            if let ipLine = lines.first(where: { $0.hasPrefix("ip=") }),
               let ip = ipLine.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) {
                newIP = ip
            }
        } else {
            // 使用原有的正则表达式解析
            do {
                let pattern = #"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"#
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let results = regex.firstMatch(in: message, options: [], range: NSRange(message.startIndex..<message.endIndex, in: message))

                results.map {
                    newIP = String(message[Range($0.range, in: message)!])
                }
            }
            catch {
                print("Unable to parse IP address.")
            }
        }
    
        return newIP
    }
    
    func updatePublicIP(_ message:String) {
        let newIP = parseIP(message)
        if !newIP.isEmpty {
            if priorIP != newIP {
                History.append(newIP + ", " + priorIP)
                hasIpChanged = true
            }
            externalIP = newIP
            priorIP = newIP
            
            // 获取地理位置信息并保存到共享存储供 Widget 使用
            fetchGeoInfo(for: newIP)
            
            // 检测代理状态
            checkProxyStatus()
        }
    }
    
    // 获取 IP 地理位置信息
    private func fetchGeoInfo(for ip: String) {
        guard let url = URL(string: "https://ipwho.is/\(ip)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let country = json["country"] as? String,
                  let city = json["city"] as? String else {
                IPService.shared.saveIP(ip)
                return
            }
            IPService.shared.saveIPInfo(IPInfo(ip: ip, country: country, countryCode: "", city: city))
        }.resume()
    }
    
    // 检测系统代理状态
    var onDirectIPUpdated: (() -> Void)?
    
    func checkProxyStatus() {
        guard let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
            IPService.shared.saveProxyStatus(false)
            return
        }
        let httpEnabled = proxies["HTTPEnable"] as? Int == 1
        let httpsEnabled = proxies["HTTPSEnable"] as? Int == 1
        let socksEnabled = proxies["SOCKSEnable"] as? Int == 1
        let hasSystemProxy = httpEnabled || httpsEnabled || socksEnabled
        
        // 如果系统设置了代理，获取直连 IP 进行比较
        if hasSystemProxy {
            getDirectIP { [weak self] in
                guard let self = self else { return }
                // 比较直连 IP 和外部 IP，如果不同才认为是真正的代理
                let actuallyUsingProxy = self.directIP != "N/A" && self.directIP != self.externalIP
                IPService.shared.saveProxyStatus(actuallyUsingProxy)
                self.onDirectIPUpdated?()
            }
        } else {
            directIP = "N/A"
            IPService.shared.saveProxyStatus(false)
        }
    }
    
    // 通过 curl --noproxy 获取直连 IP
    func getDirectIP(completion: (() -> Void)? = nil) {
        let directIPServices = [
            "http://118.184.169.48/dyndns/getip",  // 首选：3322.org IP地址（纯IP，国内）
            "http://cip.cc"                        // 备选：当前使用的服务（域名）
        ]
        
        DispatchQueue.global().async { [weak self] in
            self?.tryDirectIPService(services: directIPServices, index: 0, completion: completion)
        }
    }
    
    private func tryDirectIPService(services: [String], index: Int, completion: (() -> Void)?) {
        guard index < services.count else {
            print("All direct IP services failed")
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        
        let service = services[index]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "--noproxy", "*", "--max-time", "5", service]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                var ip: String?
                
                if service.contains("118.184.169.48") {
                    // 3322.org 返回纯IP格式
                    ip = output.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    // cip.cc 返回 "IP\t: x.x.x.x" 格式
                    let lines = output.components(separatedBy: "\n")
                    if let ipLine = lines.first(where: { $0.hasPrefix("IP") }),
                       let extractedIP = ipLine.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) {
                        ip = extractedIP
                    }
                }
                
                if let validIP = ip, !validIP.isEmpty {
                    DispatchQueue.main.async {
                        self.directIP = validIP
                        completion?()
                    }
                    return
                }
            }
        } catch {
            print("Failed to get direct IP from \(service): \(error)")
        }
        
        // 当前服务失败，尝试下一个
        self.tryDirectIPService(services: services, index: index + 1, completion: completion)
    }
    
    func getPublicIPWait(completion: (() -> Void)? = nil) {
        // 设置获取中状态
        externalIP = "获取中..."
        
        guard let url = URL(string: "https://1.1.1.1/cdn-cgi/trace") else {
            externalIP = "N/A"
            completion?()
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let data = data, error == nil,
                   let message = String(data: data, encoding: .utf8) {
                    self.updatePublicIP(message)
                } else {
                    print("Unable to get external IP from getPublicIPWait.")
                    self.externalIP = "N/A"
                    self.priorIP = self.externalIP
                }
                completion?()
            }
        }.resume()
    }

    func getPublicIPNoWait() {
        guard let downloadURL = URL(string: "https://1.1.1.1/cdn-cgi/trace") else { return }

        URLSession.shared.dataTask(with: downloadURL) { data, urlResponse, error in

            guard let data = data, error == nil, urlResponse != nil else {
                print("Unable to get external IP from getPublicIPNoWait.")
                self.externalIP = "N/A"
                self.priorIP = self.externalIP
                return
            }

            let message = String(data: data, encoding: .utf8)!
            self.updatePublicIP(message)
        }.resume()
    }

    func getInterfaceApp(_ interfaceName: String) -> String? {
        // 只检测虚拟网卡对应的应用，物理网卡返回 nil
        switch interfaceName {
        case let name where name.hasPrefix("bridge"):
            // 检查是否是 Parallels Desktop
            if FileManager.default.fileExists(atPath: "/Applications/Parallels Desktop.app") {
                // 进一步检查 Parallels 进程
                let task = Process()
                task.launchPath = "/bin/ps"
                task.arguments = ["aux"]
                
                let pipe = Pipe()
                task.standardOutput = pipe
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        if output.contains("prl_disp_service") || output.contains("Parallels") {
                            return "Parallels Desktop"
                        }
                    }
                } catch {
                    return "Parallels Desktop"
                }
            }
            
            // 检查是否是 VMware
            if FileManager.default.fileExists(atPath: "/Applications/VMware Fusion.app") {
                return "VMware Fusion"
            }
            
            return "Virtual Bridge"
            
        case let name where name.hasPrefix("vmnet"):
            return "VMware Fusion"
            
        case let name where name.hasPrefix("tun"), let name where name.hasPrefix("utun"):
            // VPN 隧道接口
            return "VPN"
            
        case let name where name.hasPrefix("tap"):
            // TAP 虚拟网卡
            return "Virtual TAP"
            
        case let name where name.hasPrefix("awdl"):
            // AirDrop/AirPlay (虚拟接口)
            return "AirDrop/AirPlay"
            
        case let name where name.hasPrefix("vboxnet"):
            // VirtualBox
            return "VirtualBox"
            
        // 物理网卡不显示应用信息
        case let name where name.hasPrefix("en"):    // Wi-Fi, 以太网
            return nil
        case let name where name.hasPrefix("lo"):    // 回环接口
            return nil
            
        default:
            return nil
        }
    }

    func getInterfaceType(_ find_name:String) -> String {
        let interfaces = SCNetworkInterfaceCopyAll() as NSArray
        for interface in interfaces {
            if let name = SCNetworkInterfaceGetBSDName(interface as! SCNetworkInterface) {
                if name as String == find_name {
                    let type = SCNetworkInterfaceGetLocalizedDisplayName(interface as! SCNetworkInterface)
                    return type! as String
                }
            }
        }

        return ""
    }

    func getMacAddress(_ find_name:String) -> String {
        let interfaces = SCNetworkInterfaceCopyAll() as NSArray
        for interface in interfaces {
            if let name = SCNetworkInterfaceGetBSDName(interface as! SCNetworkInterface) {
                if name as String == find_name {
                    let type = SCNetworkInterfaceGetHardwareAddressString(interface as! SCNetworkInterface)
                    return type! as String
                }
            }
        }

        return ""
    }

    func getIFAddresses(_ includeIP6: Bool) -> [[String:String]] {
        var interfaces = [[String:String]]()

        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return interfaces }
        guard let firstAddr = ifaddr else { return interfaces }

        // For each interface ...
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            // Check for running IPv4, IPv6 interfaces. Skip the loopback interface.
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) || (addr.sa_family == UInt8(AF_INET6) && includeIP6) {

                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if (getnameinfo(
                        ptr.pointee.ifa_addr,
                        socklen_t(addr.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                        ) == 0) {
                        var interface = [String: String]()
                        interface["name"] = String(cString: ptr.pointee.ifa_name)
                        interface["ip_address"] = String(cString: hostname)
                        interface["type"] = getInterfaceType(interface["name"]!)
                        interface["mac_address"] = getMacAddress(interface["name"]!)
                        interface["app"] = getInterfaceApp(interface["name"]!) ?? ""
                        interfaces.append(interface)
                    }
                }
            }
        }

        freeifaddrs(ifaddr)
        return interfaces
    }
}
