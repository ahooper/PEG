//
//  PEGSelf.swift
//  PEGTests
//
//  Created by Andy Hooper on 2026-01-25.
//

import Testing
@testable import PEG
import Foundation

fileprivate extension PEMachine.ParseResult {
    func succeeded()->Success? {
        return if case let .success(success) = self { success } else { nil }
    }
}

struct PEGSelf {

    @Test func grammarSelf() async throws {
//        #expect(g.start.keys == boot.start.keys)
//        let p1 = g.parse("Grammar", text, trace: false)
//        #expect(p1!.endIndex == text.endIndex)
//        
//        let g2 = PEGrammar(p1!, symbols: g.symbols)
//        #expect(g.program.count == g2.program.count)
//        #expect(g.start.keys == g2.start.keys)
//        #expect(g.program.indices.allSatisfy { g.program[$0] == g2.program[$0] })
//
//        let p2 = g2.parse("Grammar", text, trace: false)
//        assert(p2!.endIndex == text.endIndex)
        
        let c1 = PEMachine(grammar: chpegGrammar)
        let m1 = c1.parse("Grammar", chpegSource, trace: false).succeeded()!
        #expect(String.Index(utf16Offset: m1.endIndex, in: chpegSource) == chpegSource.endIndex)
        let c2 = PEMachine(chpegSource)!
        let m2 = c2.parse("Grammar", chpegSource).succeeded()!
        #expect(String.Index(utf16Offset: m2.endIndex, in: chpegSource) == chpegSource.endIndex)
        let c3 = PEMachine(chpegSource)!
        let m3 = c3.parse("Grammar", chpegSource).succeeded()
        #expect(String.Index(utf16Offset: m3!.endIndex, in: chpegSource) == chpegSource.endIndex)
        #expect(c2.core.program.count == c3.core.program.count)
        #expect(c2.core.program == c3.core.program)
        #expect(c2.symbols == c3.symbols)
        #expect(c2.core.start == c3.core.start)
    }

}
