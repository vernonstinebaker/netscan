import Foundation

public actor OUILookupService {
    public static let shared = OUILookupService()
    
    private var vendorCache: [String: String] = [:]
    private var hasLoadedData = false

    private init() {
        Task {
            await loadOUIDataIfNeeded()
        }
    }

    // Fallback helper to find the resource in either the main bundle or the bundle that defines this type
    private func urlForResource(name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        // Fall back to the bundle containing this type (useful for unit tests or when embedded in frameworks)
        return Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext)
    }

    private func loadOUIDataIfNeeded() async {
        guard !hasLoadedData else { return }

        print("[OUILookupService] Initializing and loading OUI data...")
        
        guard let url = urlForResource(name: "oui", ext: "csv") else {
            print("[OUILookupService] FATAL ERROR: oui.csv not found in bundles.")
            print("[OUILookupService] Searched in Bundle.main: \(Bundle.main.bundlePath)")
            print("[OUILookupService] Bundle.main resource path: \(Bundle.main.resourcePath ?? "nil")")
            // Try to list files in the Resources directory
            if let resourcePath = Bundle.main.resourcePath {
                do {
                    let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("[OUILookupService] Files in Resources: \(files)")
                } catch {
                    print("[OUILookupService] Error listing Resources: \(error)")
                }
            }
            return
        }
        
        print("[OUILookupService] Found oui.csv at: \(url.path)")
        
        do {
            let data = try String(contentsOf: url, encoding: .utf8)
            // Support both LF and CRLF line endings
            let normalized = data.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let lines = normalized.split(separator: "\n")
            print("[OUILookupService] Read \(lines.count) lines from oui.csv")
            
            // Skip the header line
            let dataLines = lines.dropFirst()
            print("[OUILookupService] Processing \(dataLines.count) data lines")
            
            for line in dataLines {
                // Skip empty lines
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.isEmpty { continue }
                
                // Split by comma, but be careful with quoted fields
                let columns = parseCSVLine(trimmedLine)
                guard columns.count >= 3 else {
                    print("[OUILookupService] Skipping malformed line: \(trimmedLine)")
                    continue
                }
                
                // Format: Registry,Assignment,Organization Name,Organization Address
                let registry = columns[0]
                let oui = columns[1].replacingOccurrences(of: "\"", with: "").uppercased()
                let organizationName = columns[2].replacingOccurrences(of: "\"", with: "")
                
                // Only process MA-L (MAC Address Large) entries for now
                if registry == "MA-L" {
                    vendorCache[oui] = organizationName
                }
            }
            
            hasLoadedData = true
            print("[OUILookupService] OUI data loaded successfully. \(vendorCache.count) entries.")

            // Show a few examples
            if vendorCache.isEmpty {
                print("[OUILookupService] WARNING: vendorCache is empty after parsing. First 10 raw lines:\n\(lines.prefix(10).joined(separator: "\n"))")
            } else if let firstEntry = vendorCache.first {
                print("[OUILookupService] Sample entry: \(firstEntry.key) -> \(firstEntry.value)")
            }
            
        } catch {
            print("[OUILookupService] Error loading OUI data: \(error)")
        }
    }
    
    // Helper function to parse CSV lines properly handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            if char == "," && !inQuotes {
                result.append(current)
                current = ""
                continue
            }
            current.append(char)
        }
        
        // Add the last field
        result.append(current)
        
        return result
    }

    public func findVendor(for macAddress: String?) async -> String? {
        guard let mac = macAddress else { return nil }
        let oui = String(mac.prefix(8)).replacingOccurrences(of: ":", with: "").uppercased()
        return vendorCache[oui]
    }
}

// Token class used to resolve the bundle where this file is compiled
private final class BundleToken {}
