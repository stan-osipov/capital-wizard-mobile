//
//  Validator.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import Foundation

/*
 Validator of email field
 */
struct Validator {
    static func isValidEmail(_ email: String) -> Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: email)
    }
    
    static func isValidPassword(_ password: String) -> Bool {
        return password.count >= 8
    }
    
    static func passwordsMatch(_ password: String, _ confirm: String) -> Bool {
        return password == confirm && !password.isEmpty
    }
}
