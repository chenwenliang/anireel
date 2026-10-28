import SwiftUI

struct StylePickerView: View {
    let packs: [any StylePack]
    let onSelect: (StyleID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The camera opens as soon as you pick one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(packs, id: \.descriptor.id) { pack in
                    StyleCard(descriptor: pack.descriptor) { onSelect(pack.descriptor.id) }
                }
            }
            .padding(16)
        }
        .navigationTitle("Choose a style")
    }
}

private struct StyleCard: View {
    let descriptor: StyleDescriptor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: descriptor.symbolName)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(descriptor.accent.gradient, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title).font(.headline)
                    Text(descriptor.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("The camera opens as soon as you pick one."))
    }
}
