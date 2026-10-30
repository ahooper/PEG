//
//  PEGtestCase.swift
//  pgen
//
//  Created by Andy Hooper on 2026-01-21.
//

import Testing
@testable import PEG

extension PEMachine {
    func testCase(_ name: String, _ text: String, _ tail: String?, _ errors: [String] = []) {
        let pres = parse(name, text)
        if let tail {
            switch pres {
            case let .success(s):
                #expect(text.substring(from: String.Index(utf16Offset: s.endIndex, in: text)) == tail)
            case let .failure(f):
                print("testCase", name.debugDescription, text.debugDescription, tail.debugDescription, "failure")
                #if DEBUG
                f.printFailure()
                #endif
                #expect(Bool(false))
            }
        } else {
            switch pres {
            case let .success(s):
                print("testCase", name.debugDescription, text.debugDescription, tail.debugDescription, "success", s)
                #if DEBUG
                s.printTree()
                #endif
                #expect(Bool(false))
            case let .failure(f):
                #expect(Bool(true))
            }
        }
    }
}
