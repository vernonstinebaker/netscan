import SwiftUI

struct ServiceTag: View {
    let service: NetworkService

    var body: some View {
        let s = Theme.style(for: service.type)
        HStack(spacing: 6) {
            Image(systemName: s.icon)
                .font(.system(size: 11))
            Text(s.label.uppercased())
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(s.color.opacity(0.15))
        .foregroundColor(s.color)
        .cornerRadius(6)
    }
}

struct ServiceTag_Previews: PreviewProvider {
    static var previews: some View {
        ServiceTag(service: NetworkService(name: "HTTP", type: .http))
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
