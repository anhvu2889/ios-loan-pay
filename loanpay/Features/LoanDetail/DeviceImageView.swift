import SwiftUI

/// The financed device's photo: remote, with honest intermediate states.
struct DeviceImageView: View {
    let url: URL?

    var body: some View {
        // MODERN: AsyncImage (iOS 15) replaces the URLSession-dataTask +
        // UIImage(data:) + cache-by-hand ritual. The phase switch is the
        // point: loading, success and failure each get an explicit look,
        // so a broken CDN produces a deliberate fallback instead of a
        // stuck spinner.
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                // Redacted placeholder: correct final geometry, shimmer
                // instead of spinner, no layout jump when pixels arrive.
                placeholderShape
                    .redacted(reason: .placeholder)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallbackSymbol
            @unknown default:
                fallbackSymbol
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // The photo is decoration; the device model is announced as text
        // elsewhere. Hiding it saves VoiceOver users a meaningless stop.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var placeholderShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemFill))
    }

    private var fallbackSymbol: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .overlay {
                Image(systemName: "iphone.gen3.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview("Fallback (no URL)") {
    DeviceImageView(url: nil)
        .padding()
}
