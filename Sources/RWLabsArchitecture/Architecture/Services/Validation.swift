//
//  Validation.swift
//  RWLabsArchitecture
//
//  Rule-based validation for text input
//

import Foundation

// MARK: - ValidationService

/// Validates a text value against a list of rules.
///
/// ```swift
/// let result = validation.validate(state.email, rules: [.required, .email])
/// if !result.isValid { state.emailError = result.errors.first }
/// ```
public protocol ValidationService {
    /// Checks `value` (`nil` counts as empty) against every rule and collects the failures
    func validate(_ value: String?, rules: [ValidationRule]) -> ValidationResult
}

// MARK: - ValidationRule

/// A single check on a text value.
///
/// Emptiness is only checked by `.required`. The format rules (`.email`,
/// `.phone`, `.minAge`) pass an empty value, so an optional field can be left blank.
public enum ValidationRule {
    /// Not empty after trimming whitespace
    case required
    /// At least this many characters
    case minLength(Int)
    /// At most this many characters
    case maxLength(Int)
    /// A valid email address
    case email
    /// 10–15 digits
    case phone
    /// A date (in `dateFormat`, e.g. `"yyyy-MM-dd"`) at least this many years ago
    case minAge(Int, dateFormat: String)
    /// Passes `validator`, otherwise fails with `errorMessage`
    case custom((String) -> Bool, errorMessage: String)
}

// MARK: - ValidationResult

/// The outcome of a validation: valid, or the error message of each failed rule
public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [String]

    public static let valid = ValidationResult(isValid: true, errors: [])

    public static func invalid(_ errors: [String]) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors)
    }
}

// MARK: - DefaultValidationService

/// The built-in `ValidationService`
public final class DefaultValidationService: ValidationService {
    public init() {}

    public func validate(_ value: String?, rules: [ValidationRule]) -> ValidationResult {
        let value = value ?? ""
        let isEmpty = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var errors: [String] = []

        for rule in rules {
            switch rule {
            case .required:
                if isEmpty {
                    errors.append("This field is required")
                }

            case .minLength(let length):
                if value.count < length {
                    errors.append("Minimum length is \(length) characters")
                }

            case .maxLength(let length):
                if value.count > length {
                    errors.append("Maximum length is \(length) characters")
                }

            case .email:
                if !isEmpty, !Self.matches(value, "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}") {
                    errors.append("Invalid email format")
                }

            case .phone:
                if !isEmpty, !Self.matches(value, "^[0-9]{10,15}$") {
                    errors.append("Invalid phone number")
                }

            case .minAge(let minimumAge, let dateFormat):
                guard !isEmpty else { break }
                if let birthDate = Self.dateFormatter(dateFormat).date(from: value) {
                    let age = Calendar(identifier: .gregorian).dateComponents([.year], from: birthDate, to: Date()).year
                    if let age, age < minimumAge {
                        errors.append("You must be at least \(minimumAge) years old")
                    }
                } else {
                    errors.append("Invalid date format.")
                }

            case .custom(let validator, let errorMessage):
                if !validator(value) {
                    errors.append(errorMessage)
                }
            }
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
    }

    /// Fixed locale and calendar, so a format string parses the same whatever the user's region settings
    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
}
