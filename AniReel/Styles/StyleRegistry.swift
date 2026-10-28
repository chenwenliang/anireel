struct StyleRegistry {
    static let shipping = StyleRegistry([
        NPRStylePack(),
    ])

    let packs: [any StylePack]

    init(_ packs: [any StylePack]) {
        let ids = packs.map(\.descriptor.id)
        precondition(Set(ids).count == ids.count, "Duplicate StyleID in registry: \(ids.map(\.rawValue))")
        self.packs = packs
    }

    func pack(for id: StyleID) -> (any StylePack)? {
        packs.first { $0.descriptor.id == id }
    }
}
