//
//  Component.swift
//  RWLabsArchitecture
//
//  The @Component macro, which writes a ComponentModel's boilerplate
//

// `@Component` adds `@CasePathable` to `Destination`, so apps get CasePaths with this module
@_exported import CasePaths

/// Writes the boilerplate around a `ComponentModel` subclass's nested types:
///
/// | You write | It adds |
/// |---|---|
/// | `struct State { … }` | `isLoading`, `error`, `destination: Destination?` (any that are missing) and `ViewModelState` |
/// | `enum Destination { … }` | `@CasePathable` and `ViewModelDestination` |
/// | `enum Action { … }` / `enum Output { … }` | `ViewModelAction` / `ViewModelOutput` |
/// | no `Destination` / `Action` / `Output` | `typealias Destination = EmptyDestination` (and so on) |
/// | `class Connections: ViewModelConnections<Self> { … }` | `setupConnections()` touching every `lazy var`, `lazy var connections = Connections(parent: self)`, and `HasConnections` |
///
/// ```swift
/// @Component
/// final class ProfileModel: ComponentModel<ProfileModel.State, ProfileModel.Action, ProfileModel.Output> {
///     struct State { var name = "" }
///     enum Destination { case editor(EditorModel.State) }
///     enum Action { case edit }
///     enum Output { case saved }
///
///     final class Connections: ViewModelConnections<ProfileModel> {
///         lazy var editor = Connection<EditorModel> { [weak parent] output in … }
///             .connect(state: \.destination, case: \.editor, parent: parent)
///     }
///
///     override func send(_ action: Action) {
///         switch action {
///         case .edit: destination = .editor(.init())
///         }
///     }
/// }
/// ```
///
/// Anything you declare yourself (a property, a conformance, `setupConnections()`, `connections`)
/// is left alone. The header can name a generated type (`ProfileModel.Output` with no
/// `enum Output`). A macro can't add a superclass, so the header itself stays.
///
/// Inside the model, reach optional state with `state.x` (or `self.x`); a bare `x = …` doesn't
/// go through dynamic member lookup.
@attached(memberAttribute)
@attached(member, names: named(Destination), named(Action), named(Output), named(connections))
@attached(extension, conformances: HasConnections)
public macro Component() = #externalMacro(module: "RWLabsArchitectureMacros", type: "ComponentMacro")

/// Adds `isLoading`, `error` and `destination: Destination?` (any that are missing) and
/// `ViewModelState` conformance. `@Component` applies it to `State`.
@attached(member, names: named(isLoading), named(error), named(destination))
@attached(extension, conformances: ViewModelState)
public macro ComponentState() = #externalMacro(module: "RWLabsArchitectureMacros", type: "ComponentStateMacro")

/// Adds `ViewModelDestination` conformance. `@Component` applies it to `Destination`.
@attached(extension, conformances: ViewModelDestination)
public macro ComponentDestination() = #externalMacro(module: "RWLabsArchitectureMacros", type: "ConformanceMacro")

/// Adds `ViewModelAction` conformance. `@Component` applies it to `Action`.
@attached(extension, conformances: ViewModelAction)
public macro ComponentAction() = #externalMacro(module: "RWLabsArchitectureMacros", type: "ConformanceMacro")

/// Adds `ViewModelOutput` conformance. `@Component` applies it to `Output`.
@attached(extension, conformances: ViewModelOutput)
public macro ComponentOutput() = #externalMacro(module: "RWLabsArchitectureMacros", type: "ConformanceMacro")

/// Overrides `setupConnections()` to touch every `lazy var` connection, unless the class
/// overrides it already. `@Component` applies it to `Connections`.
@attached(member, names: named(setupConnections))
public macro ComponentConnections() = #externalMacro(module: "RWLabsArchitectureMacros", type: "ComponentConnectionsMacro")
