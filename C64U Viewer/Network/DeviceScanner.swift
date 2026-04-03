// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

struct DiscoveredDevice {
    let ipAddress: String
    let info: DeviceInfo
}

final class DeviceScanner {
    private var isScanning = false
    private var scanTasks: [Task<Void, Never>] = []

    func scan(onFound: @escaping (DiscoveredDevice) -> Void, onComplete: @escaping () -> Void) {
        guard !isScanning else { return }
        isScanning = true

        // Determine subnet from local IP
        let subnet: String
        if let localIP = getLocalIP() {
            let components = localIP.split(separator: ".")
            if components.count == 4 {
                subnet = "\(components[0]).\(components[1]).\(components[2])"
            } else {
                subnet = "192.168.1"
            }
        } else {
            subnet = "192.168.1"
        }

        // Short timeout for scanning
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2.0
        let session = URLSession(configuration: config)

        let group = DispatchGroup()

        for i in 1...254 {
            group.enter()
            let ip = "\(subnet).\(i)"
            let task = Task {
                defer { group.leave() }
                guard self.isScanning else { return }

                do {
                    let url = URL(string: "http://\(ip)/v1/info")!
                    let (data, response) = try await session.data(from: url)

                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else { return }

                    let info = try JSONDecoder().decode(DeviceInfo.self, from: data)
                    DispatchQueue.main.async {
                        onFound(DiscoveredDevice(ipAddress: ip, info: info))
                    }
                } catch {
                    // Not a C64U device or unreachable — ignore
                }
            }
            scanTasks.append(task)
        }

        DispatchQueue.global().async {
            group.wait()
            DispatchQueue.main.async {
                self.isScanning = false
                self.scanTasks.removeAll()
                onComplete()
            }
        }
    }

    func scanAll(completion: @escaping ([DiscoveredDevice]) -> Void) {
        var results: [DiscoveredDevice] = []
        scan(onFound: { device in
            results.append(device)
        }, onComplete: {
            completion(results)
        })
    }

    func stop() {
        isScanning = false
        for task in scanTasks {
            task.cancel()
        }
        scanTasks.removeAll()
    }

    private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            guard (flags & (IFF_UP | IFF_RUNNING)) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  addr.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: hostname)
            }
        }
        return nil
    }
}
