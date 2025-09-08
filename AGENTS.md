# Agent Guidelines for netscan

## Build Commands
- **Build project**: `xed .` (opens in Xcode), then ⌘+B or Product > Build
- **Run tests**: `xed .`, then ⌘+U or Product > Test
- **Run single test**: In Xcode, click test diamond next to test method, or use `xcodebuild test -scheme netscan -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:netscanTests/NetworkScannerTests/testScanSubnet_EnumeratesHosts_ReportsProgress_AndSorts`

## Code Style Guidelines

### Imports
- Group imports: Foundation first, then third-party, then local modules
- Use `@testable import netscan` in test files only

### Naming Conventions
- **Types**: PascalCase (Device, NetworkScanner, ServiceType)
- **Variables/Functions**: camelCase (ipAddress, scanSubnet, deviceType)
- **Constants**: camelCase or UPPER_SNAKE for static constants
- **Enums**: PascalCase cases (case router = "router")

### Access Modifiers
- Use `public` for API-facing types and methods
- Use `private` for implementation details
- Use `internal` (default) for module-internal code

### Concurrency
- Use `actor` for thread-safe classes (NetworkScanner, PortScanner)
- Use `Sendable` protocol for data that crosses actor boundaries
- Use `Task.detached` for CPU-bound work
- Use `MainActor.run` for UI updates

### Error Handling
- Use `guard` statements for early returns
- Use `do-catch` blocks for recoverable errors
- Use `fatalError()` only for programmer errors
- Log errors with descriptive context

### Code Organization
- Use `MARK: -` comments to section code
- Group related functionality together
- Keep functions focused on single responsibility
- Use computed properties for derived data

### Testing
- Use XCTest framework
- Test files named `ClassNameTests.swift`
- Mock dependencies using protocols (PortScanning)
- Use async/await for asynchronous tests
- Test both success and failure paths