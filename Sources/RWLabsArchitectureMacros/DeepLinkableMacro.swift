//
//  DeepLinkableMacro.swift
//  RWLabsArchitectureMacros
//
//  Generates `DeepLinkable.init?(_ step:)` for a destination enum
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @DeepLinkable

/// Generates an extension with `DeepLinkable` conformance and `init?(_ step: DeepLinkStep)`.
///
/// Every case becomes a URL name: the case name, or the name given in `@DeepLink("…")`.
/// A case's single payload is built with `Payload()`, then each `params` entry is
/// copied from the step's query items with `step.assign(_:to:in:)`.
public struct DeepLinkableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw MacroError("@DeepLinkable can only be applied to an enum")
        }

        let links = try enumDecl.memberBlock.members
            .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
            .flatMap(links(in:))

        var seen = Set<String>()
        for link in links where !seen.insert(link.urlName).inserted {
            throw MacroError("@DeepLinkable: more than one case uses the URL name \"\(link.urlName)\"; give one of them a different name with @DeepLink(\"…\")")
        }

        let isPublic = enumDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.open)
        }
        let access = isPublic ? "public " : ""
        let conformance = protocols.isEmpty ? "" : ": DeepLinkable"

        let cases = links.map(\.switchCase).joined(separator: "\n")
        let source = """
        extension \(type.trimmedDescription)\(conformance) {
            \(access)init?(_ step: DeepLinkStep) {
                switch step.name {
        \(cases)
                default:
                    return nil
                }
            }
        }
        """

        guard let extensionDecl = DeclSyntax(stringLiteral: source).as(ExtensionDeclSyntax.self) else {
            throw MacroError("@DeepLinkable: couldn't generate the extension")
        }
        return [extensionDecl]
    }

    // MARK: - Reading the cases

    private struct Link {
        let urlName: String
        let caseName: String
        /// The payload's type and optional argument label, or `nil` for a case without a payload
        let payload: (type: String, label: String?)?
        /// Query item name → state property name
        let params: [(query: String, property: String)]

        var switchCase: String {
            guard let payload else {
                return """
                        case "\(urlName)":
                            self = .\(caseName)
                """
            }
            let argument = payload.label.map { "\($0): payload" } ?? "payload"
            let assigns = params.map { param in
                "            guard step.assign(\"\(param.query)\", to: \\.\(param.property), in: &payload) else { return nil }"
            }
            let declaration = params.isEmpty ? "let" : "var"
            return (["        case \"\(urlName)\":",
                     "            \(declaration) payload = \(payload.type)()"]
                    + assigns
                    + ["            self = .\(caseName)(\(argument))"])
                .joined(separator: "\n")
        }
    }

    private static func links(in caseDecl: EnumCaseDeclSyntax) throws -> [Link] {
        let options = try DeepLinkOptions(caseDecl.attributes)
        guard !options.skip else { return [] }

        if options.name != nil, caseDecl.elements.count > 1 {
            throw MacroError("@DeepLink with a name applies to a single case; declare the cases separately")
        }

        return try caseDecl.elements.map { element in
            let caseName = element.name.text
            let parameters = Array(element.parameterClause?.parameters ?? [])

            switch parameters.count {
            case 0:
                if !options.params.isEmpty {
                    throw MacroError("@DeepLink: case \(caseName) has no payload to put params into")
                }
                return Link(urlName: options.name ?? caseName, caseName: caseName, payload: nil, params: [])

            case 1:
                let parameter = parameters[0]
                let label = parameter.firstName.flatMap { $0.tokenKind == .wildcard ? nil : $0.text }
                return Link(
                    urlName: options.name ?? caseName,
                    caseName: caseName,
                    payload: (parameter.type.trimmedDescription, label),
                    params: options.params
                )

            default:
                throw MacroError("@DeepLinkable: case \(caseName) has more than one associated value; deep links support zero or one. Mark it @DeepLink(skip: true) or use a single state payload")
            }
        }
    }
}

// MARK: - @DeepLink

/// Marks a case's URL name, parameters, or exclusion. It generates nothing itself;
/// `@DeepLinkable` reads it.
public struct DeepLinkMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(EnumCaseDeclSyntax.self) else {
            throw MacroError("@DeepLink can only be applied to an enum case")
        }
        _ = try DeepLinkOptions(AttributeListSyntax([.attribute(node)]))   // validate arguments early
        return []
    }
}

// MARK: - Arguments

/// The parsed arguments of a case's `@DeepLink(…)` attribute
private struct DeepLinkOptions {
    var name: String?
    var params: [(query: String, property: String)] = []
    var skip = false

    init(_ attributes: AttributeListSyntax) throws {
        for case .attribute(let attribute) in attributes
        where attribute.attributeName.trimmedDescription == "DeepLink" {
            guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else { continue }
            for argument in arguments {
                switch argument.label?.text {
                case nil:
                    guard let value = stringLiteral(argument.expression), !value.isEmpty else {
                        throw MacroError("@DeepLink: the URL name must be a non-empty string literal")
                    }
                    name = value

                case "params":
                    params = try parseParams(argument.expression)

                case "skip":
                    guard let literal = argument.expression.as(BooleanLiteralExprSyntax.self) else {
                        throw MacroError("@DeepLink: skip must be true or false")
                    }
                    skip = literal.literal.tokenKind == .keyword(.true)

                case let label?:
                    throw MacroError("@DeepLink: unknown argument \(label)")
                }
            }
        }
    }

    private func parseParams(_ expression: ExprSyntax) throws -> [(query: String, property: String)] {
        guard let dictionary = expression.as(DictionaryExprSyntax.self) else {
            throw MacroError("@DeepLink: params must be a dictionary literal, e.g. [\"id\": \"itemId\"]")
        }
        guard case .elements(let elements) = dictionary.content else { return [] }
        return try elements.map { element in
            guard let query = stringLiteral(element.key), let property = stringLiteral(element.value) else {
                throw MacroError("@DeepLink: params keys and values must be string literals, e.g. [\"id\": \"itemId\"]")
            }
            guard isIdentifier(property) else {
                throw MacroError("@DeepLink: \"\(property)\" isn't a property name")
            }
            return (query, property)
        }
    }
}

private func stringLiteral(_ expression: ExprSyntax) -> String? {
    guard let literal = expression.as(StringLiteralExprSyntax.self),
          literal.segments.count == 1,
          case .stringSegment(let segment)? = literal.segments.first else {
        return nil
    }
    return segment.content.text
}

private func isIdentifier(_ text: String) -> Bool {
    guard let first = text.first, first.isLetter || first == "_" else { return false }
    return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
}

// MARK: - Errors

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
