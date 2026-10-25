//
//  ComponentMacro.swift
//  RWLabsArchitectureMacros
//
//  Generates the boilerplate around a ComponentModel's nested State / Destination / Action /
//  Output / Connections types
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @Component

/// Attached to a `ComponentModel` subclass:
/// - marks the nested `State`, `Destination`, `Action`, `Output` and `Connections` with their
///   `@Component…` macros (and `Destination` with `@CasePathable`);
/// - adds `typealias Destination/Action/Output = Empty…` for any of those it doesn't declare;
/// - adds `lazy var connections = Connections(parent: self)` and `HasConnections` when there's
///   a nested `Connections` class.
public struct ComponentMacro: MemberAttributeMacro, MemberMacro, ExtensionMacro {

    // MARK: Marking the nested types

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let (name, attributes) = nestedType(member) else { return [] }

        switch name {
        case "State":
            return marked(attributes, with: ["ComponentState"])
        case "Destination" where member.is(EnumDeclSyntax.self):
            return marked(attributes, with: ["CasePathable", "ComponentDestination"])
        case "Action" where member.is(EnumDeclSyntax.self):
            return marked(attributes, with: ["ComponentAction"])
        case "Output" where member.is(EnumDeclSyntax.self):
            return marked(attributes, with: ["ComponentOutput"])
        case "Connections" where member.is(ClassDeclSyntax.self):
            return marked(attributes, with: ["ComponentConnections"])
        default:
            return []
        }
    }

    // MARK: Defaults and the connections property

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            throw MacroError("@Component can only be applied to a ComponentModel subclass")
        }

        let declared = memberNames(of: declaration)
        let access = accessPrefix(of: declaration)
        var members: [DeclSyntax] = []

        if !declared.types.contains("State") {
            throw MacroError("@Component: declare a nested `struct State` (it can be empty)")
        }
        for (name, empty) in [("Destination", "EmptyDestination"), ("Action", "EmptyAction"), ("Output", "EmptyOutput")]
        where !declared.types.contains(name) {
            members.append("\(raw: access)typealias \(raw: name) = \(raw: empty)")
        }
        if declared.types.contains("Connections"), !declared.properties.contains("connections") {
            members.append("\(raw: access)lazy var connections = Connections(parent: self)")
        }
        return members
    }

    // MARK: HasConnections

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty, memberNames(of: declaration).types.contains("Connections") else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): HasConnections {}")]
    }

    // MARK: Helpers

    /// The name and attributes of a nested struct, enum or class
    private static func nestedType(_ member: some DeclSyntaxProtocol) -> (String, AttributeListSyntax)? {
        if let decl = member.as(StructDeclSyntax.self) { return (decl.name.text, decl.attributes) }
        if let decl = member.as(EnumDeclSyntax.self) { return (decl.name.text, decl.attributes) }
        if let decl = member.as(ClassDeclSyntax.self) { return (decl.name.text, decl.attributes) }
        return nil
    }

    /// `names` as attributes, leaving out any the declaration already has
    private static func marked(_ attributes: AttributeListSyntax, with names: [String]) -> [AttributeSyntax] {
        let existing = Set(attributes.compactMap { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription })
        return names
            .filter { !existing.contains($0) }
            .map { AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier($0))) }
    }
}

// MARK: - @ComponentState

/// Adds `isLoading`, `error` and `destination` (whichever are missing) and `ViewModelState`
/// conformance. `destination` is typed `Destination?`, which resolves to the enclosing model's
/// `Destination` (or `@Component`'s `EmptyDestination` default).
public struct ComponentStateMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            throw MacroError("@ComponentState can only be applied to a struct")
        }
        let declared = memberNames(of: declaration).properties
        let access = accessPrefix(of: declaration)
        var members: [DeclSyntax] = []
        if !declared.contains("isLoading") { members.append("\(raw: access)var isLoading = false") }
        if !declared.contains("error") { members.append("\(raw: access)var error: (any Error)?") }
        if !declared.contains("destination") { members.append("\(raw: access)var destination: Destination?") }
        return members
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        try ConformanceMacro.expansion(of: node, attachedTo: declaration, providingExtensionsOf: type, conformingTo: protocols, in: context)
    }
}

// MARK: - @ComponentDestination / @ComponentAction / @ComponentOutput

/// Adds the conformance its macro declaration lists (`ViewModelDestination`, `ViewModelAction`
/// or `ViewModelOutput`), unless the type already has it
public struct ConformanceMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        let list = protocols.map(\.trimmedDescription).joined(separator: ", ")
        return [try ExtensionDeclSyntax("extension \(type.trimmed): \(raw: list) {}")]
    }
}

// MARK: - @ComponentConnections

/// Overrides `setupConnections()` to touch every `lazy var`, so each connection observes its
/// parent from `init` and deep links can find it
public struct ComponentConnectionsMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            throw MacroError("@ComponentConnections can only be applied to a ViewModelConnections subclass")
        }
        let overridesSetup = declaration.memberBlock.members.contains {
            $0.decl.as(FunctionDeclSyntax.self)?.name.text == "setupConnections"
        }
        let lazyNames = declaration.memberBlock.members
            .compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { $0.modifiers.contains { $0.name.tokenKind == .keyword(.lazy) } }
            .flatMap(\.bindings)
            .compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
        guard !overridesSetup, !lazyNames.isEmpty else { return [] }

        let touches = lazyNames.map { "    _ = \($0)" }.joined(separator: "\n")
        return ["""
        \(raw: accessPrefix(of: declaration))override func setupConnections() {
            super.setupConnections()
        \(raw: touches)
        }
        """]
    }
}

// MARK: - Shared helpers

/// The type and property names a declaration group declares directly
private func memberNames(of declaration: some DeclGroupSyntax) -> (types: Set<String>, properties: Set<String>) {
    var types = Set<String>()
    var properties = Set<String>()
    for member in declaration.memberBlock.members {
        let decl = member.decl
        if let name = decl.as(StructDeclSyntax.self)?.name.text
            ?? decl.as(EnumDeclSyntax.self)?.name.text
            ?? decl.as(ClassDeclSyntax.self)?.name.text
            ?? decl.as(TypeAliasDeclSyntax.self)?.name.text {
            types.insert(name)
        } else if let variable = decl.as(VariableDeclSyntax.self) {
            for binding in variable.bindings {
                if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                    properties.insert(name)
                }
            }
        }
    }
    return (types, properties)
}

/// `"public "` when the declaration is public or open, so generated members match it
private func accessPrefix(of declaration: some DeclGroupSyntax) -> String {
    declaration.modifiers.contains {
        $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.open)
    } ? "public " : ""
}
