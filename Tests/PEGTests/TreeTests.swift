//
//  TreeTests.swift
//  PEG
//
//  Created by Andy Hooper on 2026-10-20.
//

import Testing
@testable import PEG


struct TreeTests {

    @Test func testTree1() {
        /*
                     index first next
                ┌C1    0     ⁃    1
                ├C2    1     ⁃    2
                ├C3    2     ⁃   LAST
             ┌B1┘      3     0    5
             │  ┌C4    4     ⁃   LAST
             ├B2┘      5     4   LAST
           A1┘         6     3   LAST
         */
        enum Symbol: Int, RawRepresentable, CaseIterable {
            case A1, B1, B2, C1, C2, C3, C4
        }
        var t = LinearTree<Symbol.RawValue, Void>()
        let a1 = t.mark
            let b1 = t.mark
                let c1 = t.mark
                t.end(Symbol.C1.rawValue, c1, ())
                let c2 = t.mark
                t.end(Symbol.C2.rawValue, c2, ())
                let c3 = t.mark
                t.end(Symbol.C3.rawValue, c3, ())
            t.end(Symbol.B1.rawValue, b1, ())
            let b2 = t.mark
                let c4 = t.mark
                t.end(Symbol.C4.rawValue, c4, ())
            t.end(Symbol.B2.rawValue, b2, ())
        t.end(Symbol.A1.rawValue, a1, ())
        //t.printNodes()
        //t.printTree(symbols: [Symbol](Symbol.allCases))
        
        var ci = t.childIndices(t.root)!
        #expect(ci.next() == 3)
        #expect(ci.next() == 5)
        #expect(ci.next() == nil)
        
        ci = t.childIndices(t.root)!
        ci = t.childIndices(ci.next()!)!
        #expect(ci.opt(Symbol.C1.rawValue) != nil)
        #expect(ci.opt(Symbol.C1) == nil)
        #expect(ci.next() == 1)
        #expect(ci.next() == 2)
        #expect(ci.next() == nil)
        
        ci = t.childIndices(t.root)!
        _ = ci.next()
        ci = t.childIndices(ci.next()!)!
        #expect(ci.next() == 4)
        #expect(ci.next() == nil)
        
        ci = t.childIndices(t.root)!
        #expect(Array(ci.filter(Symbol.B2.rawValue)).count == 1)
    }

}
