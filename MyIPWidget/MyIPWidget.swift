//
//  MyIPWidget.swift
//  MyIPWidget
//
//  Created by 史海涛 on 2025/12/13.
//  Copyright © 2025 pholex@gmail.com. All rights reserved.
//

import WidgetKit
import SwiftUI
import Network

// MARK: - Timeline Entry

struct IPEntry: TimelineEntry {
    let date: Date
    let ip: String
    let country: String
    let city: String
    let isProxy: Bool
}

// MARK: - Timeline Provider

struct IPProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> IPEntry {
        IPEntry(date: Date(), ip: "192.168.1.1", country: "Unknown", city: "Unknown", isProxy: false)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (IPEntry) -> Void) {
        let info = IPService.shared.cachedIPInfo
        let entry = IPEntry(
            date: Date(), 
            ip: info?.ip ?? "获取中...", 
            country: info?.country ?? "正在连接", 
            city: info?.city ?? "",
            isProxy: IPService.shared.isProxy
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<IPEntry>) -> Void) {
        Task {
            var entry: IPEntry
            var nextUpdateMinutes = 15
            
            // 获取 IP，代理状态从 App Group 读取
            if let result = await fetchIPDirectly() {
                IPService.shared.saveIPInfo(IPInfo(ip: result.ip, country: result.country, countryCode: "", city: result.city))
                entry = IPEntry(date: Date(), ip: result.ip, country: result.country, city: result.city, isProxy: IPService.shared.isProxy)
            } else if let cached = IPService.shared.cachedIPInfo {
                entry = IPEntry(date: Date(), ip: cached.ip, country: cached.country, city: cached.city, isProxy: IPService.shared.isProxy)
                nextUpdateMinutes = 3
            } else {
                entry = IPEntry(date: Date(), ip: "连接中", country: "网络初始化", city: "", isProxy: false)
                nextUpdateMinutes = 1
            }
            
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: nextUpdateMinutes, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    // 获取 IP
    private func fetchIPDirectly() async -> (ip: String, country: String, city: String)? {
        guard let url = URL(string: "https://ipwho.is/") else { return nil }
        
        do {
            let request = URLRequest(url: url, timeoutInterval: 5)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = json["ip"] as? String,
               let country = json["country"] as? String,
               let city = json["city"] as? String {
                return (ip, country, city)
            }
        } catch {
            print("Widget fetch error: \(error)")
        }
        return nil
    }
    
    // 检查网络连接状态
    private func checkNetworkConnectivity() async -> Bool {
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "NetworkMonitor")
            
            monitor.pathUpdateHandler = { path in
                let isConnected = path.status == .satisfied
                monitor.cancel()
                continuation.resume(returning: isConnected)
            }
            
            monitor.start(queue: queue)
            
            // 超时处理
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                monitor.cancel()
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - Widget View

struct MyIPWidgetEntryView: View {
    var entry: IPEntry
    
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }
    
    var smallView: some View {
        VStack(spacing: 6) {
            Image(systemName: getNetworkIcon())
                .font(.title)
                .foregroundColor(getNetworkColor())
            
            if isNetworkInitializing() {
                Text("网络初始化中")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("请稍候")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if entry.ip == "N/A" {
                Text("网络连接中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("请稍候")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 4) {
                    Text(entry.city == entry.country ? entry.city : "\(entry.country), \(entry.city)")
                    if entry.isProxy {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.blue)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                Text(entry.ip)
                    .font(.system(.title3, design: .monospaced))
                    .bold()
                    .minimumScaleFactor(0.6)
            }
        }
    }
    
    var mediumView: some View {
        HStack {
            Image(systemName: getNetworkIcon())
                .font(.system(size: 40))
                .foregroundColor(getNetworkColor())
            
            VStack(alignment: .leading, spacing: 6) {
                if isNetworkInitializing() {
                    Text("网络初始化中...")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("系统启动阶段，请稍候")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if entry.ip == "N/A" {
                    Text("网络连接中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("正在获取IP地址")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text(entry.city == entry.country ? entry.city : "\(entry.country), \(entry.city)")
                        if entry.isProxy {
                            Image(systemName: "shield.fill")
                                .foregroundColor(.blue)
                            Text("PROXY")
                                .foregroundColor(.blue)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    Text(entry.ip)
                        .font(.system(.title, design: .monospaced))
                        .bold()
                }
            }
            Spacer()
        }
    }
    
    private func isNetworkInitializing() -> Bool {
        return entry.ip == "连接中" && entry.country == "网络初始化"
    }
    
    private func getNetworkIcon() -> String {
        if isNetworkInitializing() {
            return "wifi.exclamationmark"
        } else if entry.ip == "N/A" || entry.ip == "连接中" {
            return "wifi.slash"
        } else {
            return "network"
        }
    }
    
    private func getNetworkColor() -> Color {
        if isNetworkInitializing() {
            return .orange
        } else if entry.ip == "N/A" || entry.ip == "连接中" {
            return .red
        } else {
            return .green
        }
    }
}

// MARK: - Widget Configuration

@main
struct MyIPWidget: Widget {
    let kind: String = "MyIPWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IPProvider()) { entry in
            if #available(macOS 14.0, *) {
                MyIPWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                MyIPWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("My IP")
        .description("显示当前外部 IP 地址")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    MyIPWidget()
} timeline: {
    IPEntry(date: Date(), ip: "54.199.86.109", country: "Japan", city: "Tokyo", isProxy: false)
    IPEntry(date: Date(), ip: "54.199.86.109", country: "Japan", city: "Tokyo", isProxy: true)
}

#Preview(as: .systemMedium) {
    MyIPWidget()
} timeline: {
    IPEntry(date: Date(), ip: "54.199.86.109", country: "Japan", city: "Tokyo", isProxy: false)
    IPEntry(date: Date(), ip: "54.199.86.109", country: "Japan", city: "Tokyo", isProxy: true)
}
