//
//  PECases.swift
//  PEGTests
//
//  Created by Andy Hooper on 2026-01-21.
//

import Testing
@testable import PEG

struct PECases {

    @Test func topChoice() async throws {
        enum Sym: Int, CaseIterable {
            case s, p
        }
        let g: PEMachine<Sym>.Builder.Bootstrap = [
            .s: .alt([.lit("ee"), .lit("ff"), .lit("gg")]),
            .p: .seq([.call(.s), .rep1(.call(.s))]),
        ]
        let t = PEMachine(grammar: g)
        t.testCase("s", "ffgg", "gg")
        t.testCase("s", "xx", nil)
        t.testCase("p", "ffggee", "")
        t.testCase("p", "ffxx", nil)
    }

    @Test func PEcases() async throws {
        enum Sym: Int, CaseIterable {
            case E, F, G
            case Choice, Sequence, Test, Not, Repeat0, Repeat1, Option, Identifier, Literal, CharClass, Dot
        }
        let g: PEMachine<Sym>.Builder.Bootstrap = [
            
            .E: .lit("E"),
            .F: .lit("F"),
            .G: .lit("G"),
            
            .Choice: .alt([
                .call(.E), .call(.F), .call(.G),]),
            .Sequence: .seq([
                .call(.E), .call(.F), .call(.G),]),
            .Test: .pred(.call(.E)),
            .Not: .not(.call(.E)),
            .Repeat0: .rep(.call(.E)),
            .Repeat1: .rep1(.call(.E)),
            .Option: .opt(.call(.E)),
                   
            .Identifier: .call(.Identifier),
            .Literal: .lit("literal"),
            .CharClass: .chrs("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"),
            .Dot: .any(1),

            ]

        for (name, text, tail) in [
            
                ("Literal", "literal", ""),
                ("Literal", "Literal", nil),
                ("Literal", "Lit", nil),

                ("Dot", "abc", "bc"),
                ("Dot", "", nil),
                
                ("CharClass", "abc", "bc"),
                ("CharClass", "123", nil),
                ("CharClass", "", nil),
        
                ("Sequence", "EFGH", "H"),
                ("Sequence", "EF", nil),
                ("Sequence", "", nil),

                ("Choice", "EFGH", "FGH"),
                ("Choice", "AF", nil),
                ("Choice", "", nil),

                ("Test", "EF", "EF"),
                ("Test", "AF", nil),
                
                ("Not", "EF", nil),
                ("Not", "AF", "AF"),
                
                ("Repeat0", "EEEx", "x"),
                ("Repeat0", "x", "x"),
                ("Repeat0", "", ""),
                
                ("Repeat1", "EEEx", "x"),
                ("Repeat1", "Ex", "x"),
                ("Repeat1", "x", nil),
                ("Repeat1", "", nil),
                
                ("Option", "Ex", "x"),
                ("Option", "x", "x"),
                ("Option", "", ""),

        ] {
            PEMachine(grammar: g).testCase(name, text, tail)
        }
    }

    @Test func PECharExtensions() async throws {
        enum Sym: Int, CaseIterable {
            case Char, CharSet, CharRange, SpanClass, SpanSet
        }
        let g: PEMachine<Sym>.Builder.Bootstrap = [

            .Char: .lit("c"),
            .CharSet: .chrs(" \t\n\r"),
            .CharRange: .chrs("0123456789"),
            .SpanClass: .rep(.chrs("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")),
            .SpanSet: .rep(.chrs(" \t\n\r")),
            ]

        for (name, text, tail) in [
            
                ("Char", "c", ""),
                ("Char", "cc", "c"),
                ("Char", "", nil),

                ("CharSet", " ", ""),
                ("CharSet", "\t", ""),
                ("CharSet", "\r", ""),
                ("CharSet", "\n", ""),
                ("CharSet", "x", nil),
                ("CharSet", "", nil),
                
                ("CharRange", "0", ""),
                ("CharRange", "x", nil),
                ("CharRange", "", nil),
                
                ("SpanClass", "abcABC123 ", " "),
                ("SpanClass", " ", " "),
                ("SpanClass", "", ""),
                
                ("SpanSet", "   ", ""),
                ("SpanSet", "   x", "x"),
                ("SpanSet", "", ""),

        ] {
     PEMachine(grammar: g).testCase(name, text, tail)
        }
    }

}
