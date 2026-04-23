import Foundation

/// Maps command identifiers (from KeyboardBindings or future toolbar
/// buttons) to the primitive type that performs the mutation.
enum MutationResolver {
    private static let registry: [String: MutationPrimitive.Type] = [
        BoldMutation.identifier: BoldMutation.self,
        ItalicMutation.identifier: ItalicMutation.self,
        InlineCodeMutation.identifier: InlineCodeMutation.self,
        LinkMutation.identifier: LinkMutation.self,
        BodyMutation.identifier: BodyMutation.self,
        Heading1Mutation.identifier: Heading1Mutation.self,
        Heading2Mutation.identifier: Heading2Mutation.self,
        Heading3Mutation.identifier: Heading3Mutation.self,
        Heading4Mutation.identifier: Heading4Mutation.self,
        Heading5Mutation.identifier: Heading5Mutation.self,
        Heading6Mutation.identifier: Heading6Mutation.self,
        BulletListMutation.identifier: BulletListMutation.self,
        NumberedListMutation.identifier: NumberedListMutation.self,
    ]

    static func primitive(for identifier: String) -> MutationPrimitive.Type? {
        registry[identifier]
    }
}
