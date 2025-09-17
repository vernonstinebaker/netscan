# Project Roadmap: Netscan Feature Enhancement

This document outlines the step-by-step plan to add the additional features depicted in the screenshots to the netscan application.

## ✅ COMPLETED: Core Infrastructure & UI

### 1. Data Models - ✅ COMPLETE

- [x] **Update `Device` Model:**
  - ✅ Add properties: `hostname`, `vendor`, `services`, `firstSeen`, `lastSeen`
  - ✅ Add `OperatingSystem` enum for device type (`unknown`, `linux`, `windows`, `macOS`, `iOS`, `android`, `router`, `printer`, `tv`)
- [x] **Create `Port` Model:**
  - ✅ Define a new `Port` struct
  - ✅ Add properties: `port` (Int), `serviceName` (String), `status` (enum: `open`, `closed`, `filtered`)

### 2. Scanning Capabilities - ✅ COMPLETE

- [x] **Create `PortScanner` Service:**
  - ✅ Implement POSIX socket-based port scanning
  - ✅ Identify open ports and services running on them
  - ✅ Handle connection timeouts and error states
- [x] **Update `NetworkScanner` Service:**
  - ✅ Integrate the new `PortScanner`
  - ✅ Add vendor lookup functionality based on MAC addresses (ARP + OUI database integrated)
  - ✅ Implement basic device type classification (rules using hostname/vendor/ports)
  - ✅ Add DNS‑SD type discovery to seed Bonjour browsing dynamically
  - ✅ Add WS‑Discovery probe (UDP 3702) to complement SSDP
  - ✅ Overlap ARP with Bonjour/SSDP/WS‑Discovery for earlier enrichment

### 3. ViewModels - ✅ COMPLETE

- [x] **Update `ScanViewModel`:**
  - ✅ Manage new data from enhanced scanner
  - ✅ Expose properties for device list, summary counts
  - ✅ Manage currently selected device for detail view
  - ✅ Implement de-duplication and IP-based sorting
  - ✅ Implement robust scan cancellation

### 4. User Interface - ✅ COMPLETE

- [x] **Redesign `DeviceRowView`:**
  - ✅ Add device icon and status indicators
  - ✅ Display device name, IP address, MAC address
  - ✅ Show list of detected services
- [x] **Update `ContentView`:**
  - ✅ Add top bar with network information (SSID and local IP)
  - ✅ Implement new device list style with NavigationSplitView
  - ✅ Add summary bar at bottom with device counts
  - ✅ Restore explicit Scan/Stop buttons and fix layout shift issues
  - ✅ Fix scrolling behavior to use full window height
- [x] **Overhaul `DeviceDetailView`:**
  - ✅ Display detailed network information
  - ✅ Add "copy to clipboard" functionality for IP and MAC addresses
  - ✅ Show active services and port scan results

### 5. Build System & IDE Integration - ✅ COMPLETE

- [x] **Swift Package Manager Setup:**
  - ✅ Configure executable target for GUI app
  - ✅ Fix duplicate symbol issues
  - ✅ Resolve resource handling conflicts
- [x] **VS Code Integration:**
  - ✅ Create proper launch.json configurations
  - ✅ Add build tasks for Debug/Release
  - ✅ Enable debugging and GUI launching from IDE
- [x] **Swift 6 Compatibility:**
  - ✅ Fix conformance isolation warnings with @preconcurrency
  - ✅ Update actor isolation patterns
  - ✅ Clean up debug logging
  - ✅ Resolve all build warnings
  - ✅ Treat warnings as errors (Swift and C)

## 🚀 NEXT STEPS: Advanced Features & Polish

### 6. Enhanced Device Detection

- [x] **MAC Address Vendor Lookup:**
  - ✅ OUI (Organizationally Unique Identifier) database bundled and parsed
  - ✅ Vendor identification integrated with ARP MAC parsing
  - ✅ In‑memory vendor cache for performance
- [x] **Service Detection Enhancement:**
  - ✅ Improve service name detection accuracy (central ServiceMapper; port‑based mapping)
  - ⏳ Version detection for common services
  - ⏳ Service fingerprinting
- [x] **Device Type Classification:**
  - ✅ Initial rules using hostname/vendor/ports
  - ⏳ Add capability/OS detection depth and confidence scoring

### 7. Performance & Reliability

- [x] **Scanning Optimization:**
  - ✅ Implement concurrent port scanning with proper limits (32 concurrent connections)
  - ✅ Add scan progress tracking and cancellation support
  - ✅ Optimize network discovery with skipIPs to avoid redundant scanning
  - [ ] Add advanced performance tuning options
- [ ] **Caching & Persistence:**
  - ⏳ Persist device information between scans via SwiftData integration
  - ⏳ Add scan history and comparison features
- [ ] **Error Handling & Recovery:**
  - Improve error handling for network timeouts
  - Add retry logic for failed scans
  - Implement graceful degradation for partial failures

### 8. User Experience Enhancements

- [x] **Advanced Filtering & Search:**
  - ✅ Implement search (name, IP, vendor, hostname, MAC, services)
  - ✅ Add filters (online only, device type, discovery source)
  - ⏳ Vendor‑specific filter and custom device grouping
- [ ] **Device Details Enhancements:**
  - [ ] Add "Complete Port Scan" action to scan all 65535 ports (with progress indicator)
  - [ ] Show detailed port scan results with service identification
  - [ ] Add port scan history and comparison features
- [ ] **Export & Reporting:**
  - Export scan results to CSV/JSON
  - Generate network topology reports
  - Add PDF report generation
- [ ] **Real-time Updates:**
  - ✅ Implement live device status monitoring with progressive loading
  - ✅ Add notification for new device discovery (devices appear immediately)
  - ✅ Show real-time scan progress with device counts
  - [ ] Add device status change notifications

### 🎯 **Immediate Next Priorities:**

1.  **Device Details Enhancement** - Add complete port scan functionality from Device Details page
2.  **Service Insight** - Version detection and lightweight fingerprinting for common services.
3.  **Classification** - Deeper OS/capability detection with confidence scoring.
4.  **Performance** - Advanced tuning (dynamic concurrency, large subnet strategies).
5.  **Advanced UX** - Vendor filter, custom grouping, export/reporting.

---

## 🔧 2025-09-08 Work Log (Ongoing)

This section tracks incremental fixes and tests as they land.

- [x] **Phase 1 Optimization**: Removed low-value discovery methods (NTPDiscoverer, NetBIOSDiscoverer) to focus on home network use cases
- [x] **Phase 2 Optimization**: Implemented tiered discovery system with reduced timeouts and improved performance
  - [x] Tier 1: Fast methods (Bonjour + ARP) with 3.0s timeout
  - [x] Tier 2: Medium methods (SSDP + WS-Discovery) with 2.0-3.0s timeout
  - [x] Immediate device updates and service scanning when devices are discovered
- [x] **Tiered Service Scanning**: Prioritized common home network ports (HTTP, HTTPS, SSH, DNS, Telnet first)
- [x] **KV Store Integration**: Load previous scan data first, then immediately check device online status
- [x] **Swift 6 Compatibility**: Fixed main actor isolation warnings for NetworkService creation and debugLog calls
- [x] Fix: Preserve/merge `openPorts` in `ScanViewModel.updateDevice` instead of overwriting. Add unit tests for port/service merge semantics. (2025-09-04)
- [x] Improve: Service mapping accuracy
  - [x] `BonjourCollector.mapServiceType` returns `.unknown` for unmapped types
  - [x] Use `ServiceCatalog.entry(forPort:)` in Port-derived mapping and UI
  - [x] Unit tests for mapping by port and mDNS type
- [x] UX: Distinguish services by port and show it in pills (e.g., HTTP:8080). Avoid merging different ports under one service type. (2025-09-04)
- [x] Relax: Remove `.wifi` interface requirement in `NetworkFrameworkProber`
  - [x] Add smoke test that `probe` returns `.dead` for invalid IP (no network needed)
- [x] Reliability: Make per-host port scans cancellable via DI in `ScanViewModel`
  - [x] Inject `portScannerFactory` and track child tasks; cancel on `cancelScan()`
  - [x] Unit tests using a fake scanner to verify cancellation and state cleanup
- [x] Polish: Gate noisy logs under `#if DEBUG` for Bonjour, SSDP, OUI (selective), scanners
- [x] Tests: Updated and added unit tests for mapping, merging, prober, WS‑Discovery parsing, filtering; full suite runs clean
