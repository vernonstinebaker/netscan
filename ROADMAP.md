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
  - ⏳ Add vendor lookup functionality based on MAC addresses (MAC addresses not collected, OUI database not implemented)
  - ⏳ Implement logic to determine device type/OS (all devices show as "unknown")

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

## 🚀 NEXT STEPS: Advanced Features & Polish

### 6. Enhanced Device Detection

- [ ] **MAC Address Vendor Lookup:**
  - Implement OUI (Organizationally Unique Identifier) database
  - Add vendor identification for network devices
  - Cache vendor data for performance
- [ ] **Service Detection Enhancement:**
  - Improve service name detection accuracy
  - Add version detection for common services
  - Implement service fingerprinting
- [ ] **Device Type Classification:**
  - Enhance OS detection algorithms
  - Add device capability detection (IoT, mobile, desktop)
  - Implement confidence scoring for classifications

### 7. Performance & Reliability

- [x] **Scanning Optimization:**
  - ✅ Implement concurrent port scanning with proper limits (32 concurrent connections)
  - ✅ Add scan progress tracking and cancellation support
  - ✅ Optimize network discovery with skipIPs to avoid redundant scanning
  - [ ] Add advanced performance tuning options
- [ ] **Caching & Persistence:**
  - Cache device information between scans
  - Persist scan results to disk
  - Add scan history and comparison features
- [ ] **Error Handling & Recovery:**
  - Improve error handling for network timeouts
  - Add retry logic for failed scans
  - Implement graceful degradation for partial failures

### 8. User Experience Enhancements

- [ ] **Advanced Filtering & Search:**
  - Add device filtering by type, status, vendor
  - Implement search functionality
  - Add custom device grouping
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

1.  **MAC Address Collection** - Implement ARP table parsing to collect device MAC addresses
2.  **OUI Database Integration** - Bundle compressed OUI database for vendor lookup
3.  **Device Type Classification** - Implement rules engine for device type determination
4.  **Persistence** - Cache device information between scans and persist results.
5.  **Advanced UX** - Implement search, filtering, and export capabilities.

---

## 🔧 2025-09-04 Work Log (Ongoing)

This section tracks incremental fixes and tests as they land.

- [x] Fix: Preserve/merge `openPorts` in `ScanViewModel.updateDevice` instead of overwriting. Add unit tests for port/service merge semantics. (2025-09-04)
- [x] Improve: Service mapping accuracy
  - [x] `BonjourCollector.mapServiceType` returns `.unknown` for unmapped types
  - [x] Use `ServiceCatalog.entry(forPort:)` in Port-derived mapping and UI
  - [x] Unit tests for mapping by port and mDNS type
- [x] Relax: Remove `.wifi` interface requirement in `NetworkFrameworkProber`
  - [x] Add smoke test that `probe` returns `.dead` for invalid IP (no network needed)
- [x] Reliability: Make per-host port scans cancellable via DI in `ScanViewModel`
  - [x] Inject `portScannerFactory` and track child tasks; cancel on `cancelScan()`
  - [x] Unit tests using a fake scanner to verify cancellation and state cleanup
- [ ] Polish: Gate noisy logs under `#if DEBUG` for Bonjour, SSDP, OUI, NIO scanners
- [ ] Tests: Run full test suite after each step; keep ROADMAP updated.
