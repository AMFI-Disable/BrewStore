import AppKit
import SwiftUI

struct PackageIconView: View {
    let name: String
    let kind: BrewPackageKind
    let applicationNames: [String]
    let iconURL: URL?
    var size: CGFloat = 34
    var cornerRadius: CGFloat = 7

    init(
        package: BrewStorePackage,
        size: CGFloat = 34,
        cornerRadius: CGFloat = 7
    ) {
        self.name = package.name
        self.kind = package.kind
        self.applicationNames = package.applicationNames
        self.iconURL = package.iconURL
        self.size = size
        self.cornerRadius = cornerRadius
    }

    init(
        item: BrewStoreDiscoveryItem,
        installedPackage: BrewStorePackage? = nil,
        size: CGFloat = 34,
        cornerRadius: CGFloat = 7
    ) {
        self.name = item.name
        self.kind = item.kind
        self.applicationNames = installedPackage?.applicationNames ?? []
        self.iconURL = item.iconURL
        self.size = size
        self.cornerRadius = cornerRadius
    }

    init(
        name: String,
        kind: BrewPackageKind,
        applicationNames: [String] = [],
        iconURL: URL? = nil,
        size: CGFloat = 34,
        cornerRadius: CGFloat = 7
    ) {
        self.name = name
        self.kind = kind
        self.applicationNames = applicationNames
        self.iconURL = iconURL
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            if kind == .cask,
               let icon = BrewStoreAppIconResolver.localAppIcon(
                for: applicationNames.isEmpty ? [name] : applicationNames
               ) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else if phase.error != nil {
                        fallbackView
                    } else {
                        fallbackView
                            .opacity(0.4)
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .background(
            Color.accentColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallbackView: some View {
        Image(systemName: kind == .cask ? "app.fill" : "terminal.fill")
            .font(.system(size: max(10, size * 0.45)))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
    }
}
