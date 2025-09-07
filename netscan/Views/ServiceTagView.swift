import SwiftUI

struct ServiceTag: View {
    let service: NetworkService
    var showNonStandardPort: Bool = false

    var body: some View {
        let s = Theme.style(for: service.type)
        HStack(spacing: 6) {
            Image(systemName: s.icon)
                .font(.system(size: 11))
            Text(displayLabel(s.label))
                .font(.system(size: 12, weight: .semibold))
                // allow the text to use its intrinsic width so the pill expands instead of truncating
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(s.color.opacity(0.15))
        .foregroundColor(s.color)
        .cornerRadius(6)
        .accessibilityLabel(displayLabel(s.label))
    }

    private func displayLabel(_ base: String) -> String {
        guard showNonStandardPort, let p = service.port else { return base.uppercased() }
        switch service.type {
        case .http where p != 80,
             .https where p != 443,
             .ssh where p != 22:
            return "\(base.uppercased()):\(p)"
        default:
            return base.uppercased()
        }
    }
}

struct ServiceTag_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            ServiceTag(service: NetworkService(name: "HTTP", type: .http))
            ServiceTag(service: NetworkService(name: "HTTP", type: .http, port: 8080), showNonStandardPort: true)
        }
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
