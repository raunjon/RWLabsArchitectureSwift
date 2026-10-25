//
//  Plugin.swift
//  RWLabsArchitectureMacros
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct RWLabsArchitectureMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DeepLinkableMacro.self,
        DeepLinkMacro.self,
        ComponentMacro.self,
        ComponentStateMacro.self,
        ConformanceMacro.self,
        ComponentConnectionsMacro.self,
    ]
}
