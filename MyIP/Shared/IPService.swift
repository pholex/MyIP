//
//  IPService.swift
//  IP Connect
//
//  Shared IP fetching service for App and Widget
//

import Foundation

// MARK: - IP Info Model

public struct IPInfo: Codable {
    public let ip: String
    public let country: String
    public let countryCode: String
    public let city: String
}

public class IPService {
    
    public static let shared = IPService()
    
    // App Group identifier
    public static let appGroupID = "group.cn.nexusdeep.myip"
    
    // UserDefaults keys
    private static let ipKey = "cachedExternalIP"
    private static let countryKey = "cachedCountry"
    private static let countryCodeKey = "cachedCountryCode"
    private static let cityKey = "cachedCity"
    private static let lastUpdateKey = "lastIPUpdateTime"
    private static let isProxyKey = "isProxy"
    
    private init() {}
    
    // MARK: - Async IP Fetching
    
    public func fetchIPInfo() async -> IPInfo? {
        guard let url = URL(string: "http://ip-api.com/json/") else {
            return cachedIPInfo
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(IPAPIResponse.self, from: data)
            let info = IPInfo(ip: response.query, country: response.country, countryCode: response.countryCode, city: response.city)
            saveIPInfo(info)
            return info
        } catch {
            print("Failed to fetch IP info: \(error)")
        }
        
        return cachedIPInfo
    }
    
    public func fetchExternalIP() async -> String {
        if let info = await fetchIPInfo() {
            return info.ip
        }
        return cachedIP ?? "N/A"
    }
    
    // MARK: - Cache Management
    
    public var cachedIP: String? {
        return sharedDefaults?.string(forKey: Self.ipKey)
    }
    
    public var cachedIPInfo: IPInfo? {
        guard let ip = sharedDefaults?.string(forKey: Self.ipKey),
              let country = sharedDefaults?.string(forKey: Self.countryKey),
              let countryCode = sharedDefaults?.string(forKey: Self.countryCodeKey),
              let city = sharedDefaults?.string(forKey: Self.cityKey) else {
            return nil
        }
        return IPInfo(ip: ip, country: country, countryCode: countryCode, city: city)
    }
    
    public var lastUpdateTime: Date? {
        return sharedDefaults?.object(forKey: Self.lastUpdateKey) as? Date
    }
    
    public func saveIP(_ ip: String) {
        sharedDefaults?.set(ip, forKey: Self.ipKey)
        sharedDefaults?.set(Date(), forKey: Self.lastUpdateKey)
    }
    
    public func saveIPInfo(_ info: IPInfo) {
        sharedDefaults?.set(info.ip, forKey: Self.ipKey)
        sharedDefaults?.set(info.country, forKey: Self.countryKey)
        sharedDefaults?.set(info.countryCode, forKey: Self.countryCodeKey)
        sharedDefaults?.set(info.city, forKey: Self.cityKey)
        sharedDefaults?.set(Date(), forKey: Self.lastUpdateKey)
    }
    
    public func saveProxyStatus(_ isProxy: Bool) {
        sharedDefaults?.set(isProxy, forKey: Self.isProxyKey)
    }
    
    public var isProxy: Bool {
        return sharedDefaults?.bool(forKey: Self.isProxyKey) ?? false
    }
    
    private var sharedDefaults: UserDefaults? {
        return UserDefaults(suiteName: Self.appGroupID)
    }
}

// MARK: - ip-api.com Response

private struct IPAPIResponse: Codable {
    let query: String
    let country: String
    let countryCode: String
    let city: String
}
