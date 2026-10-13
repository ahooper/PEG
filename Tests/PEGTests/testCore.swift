//
//  testCore.swift
//  pgen
//
//  From cpp-peglib Copyright (c) 2022 yhirose
//  License: https://github.com/yhirose/cpp-peglib/blob/master/LICENSE
//  https://github.com/yhirose/cpp-peglib/blob/master/test/test_core.cc
//

import Testing
@testable import PEG

fileprivate extension PEMachine.ParseResult {
    func succeeded()->Success? {
        return if case let .success(success) = self { success } else { nil }
    }
}

struct testCore {

    @Test func simpleSyntax() {
        let _ = PEMachine("""
            ROOT <- _
            _ <- ' '
            """)
        #expect(true)
    }

    @Test func emptySyntax() async {
        // https://www.theswift.dev/posts/swift-testing-exit-tests-fatalerror/
        // await #expect(processExitsWith: .failure) {
        let p = PEMachine("""
            """)
        #expect(p == nil)
    }

    @Test func backslashEscapeSequence() {
        let _ = PEMachine(#"""
                    ROOT <- _
                    _ <- '\\'
            """#)
        #expect(true)
    }
    
    
    @Test func debugEscapeSequence() async {
        //let g = chpegGrammar
        enum Sym: Int, CaseIterable { case Literal, Char, EscChar, PlainChar }
        let g: PEMachine<Sym>.Builder.Bootstrap = [
            .Literal:
                            .seq([
                                .lit("'"),
                                .rep(
                                    .seq([
                                        .not(.lit("'")),
                                        .call(.Char)
                                        ])
                                    ),
                                .lit("'"),
                                ]),
            // Char        { } <- EscChar / OctChar / PlainChar
            .Char:
                        .alt([
                            .call(.EscChar),
                            .call(.PlainChar),
                            ]),
            // EscChar     {L} <- '\\' [nrt'"\[\]\\]
            .EscChar:
                        .seq([
                            .lit("\\"),
                            .chrs("nrt'\"[]\\"),
                           ]),
            // PlainChar   {L} <- !'\\' .
            .PlainChar:
                        .seq([
                            .not(.lit("\\")),
                            .any(1)
                            ]),
            ]
        let p = PEMachine(grammar: g)
        //p.printProgram()
        let t = #"""
                '\'
                """#
        let r = p.parse(Sym.Literal, t, trace: false)
        #expect(r.succeeded() == nil)
    }
    
    @Test func invalidEscapeSequence() async {
        // https://www.theswift.dev/posts/swift-testing-exit-tests-fatalerror/
       let bad = PEMachine(#"""
                ROOT <- _
                _ <- '\'
                """#)
        #expect(bad == nil)
    }

    @Test func stringCapture() {
        let grammar = PEMachine("""
            ROOT      <-  _ ('[' TAG_NAME ']' _)*
            TAG_NAME  <-  (!']' .)+
            _         <-  [ \t]*

            """)!,
            text = " [tag1] [tag:2] [tag-3] ",
            parse = grammar.parse("ROOT", text).succeeded()
        #expect(parse!.endIndex == text.endIndex)
        //parse!.tree.printTree(symbols: parse!.symbols)
        let root = parse!.tree.root
        #expect(parse!.tree[root].has(grammar.symbolIndex("ROOT")!))
        //let tags = Array( parse!.tree.childIndices(root)!.filter{ parse!.tree[$0].has(grammar.symbol("TAG_NAME")!) }
        let tags = Array( parse!.tree.childIndices(root)!.filter(grammar.symbolIndex("TAG_NAME")!)
                    .map{ parse!.nodeString($0) } )
        //print(tags)
        #expect(tags == ["tag1","tag:2","tag-3"])
    }

    @Test func PEStringCapture() {
        enum Sym: Int, CaseIterable { case ROOT, TAG, TAG_NAME, _WS }
        let grammar: PEMachine<Sym>.Builder.Bootstrap = [
            .ROOT:  .seq([.call(._WS),
                           .rep(.call(.TAG))]),
            .TAG:   .seq([.lit("["),
                          .call(.TAG_NAME),
                          .lit("]"),
                          .call(._WS)]),
            .TAG_NAME:
                     .rep1(.seq([.not(.lit("]")),
                                         .any(1)])),
            ._WS:
                     .rep(.chrs(" \t")),
                ],
            parser = PEMachine(grammar: grammar),
            text = " [tag1] [tag:2] [tag-3] ",
            parse = parser.parse("ROOT", text).succeeded()
        #expect(parse!.endIndex == text.endIndex)
        //parse!.tree.printTree(symbols: parse!.symbols)
        let root = parse!.tree.root
        #expect(parse!.tree[root].has(parser.symbolIndex("ROOT")!))
        let tags = Array(parse!.tree.childIndices(root)!.filter(parser.symbolIndex("TAG")!)),
            names = Array(tags.map { Array(parse!.tree.childIndices($0)!.filter(parser.symbolIndex("TAG_NAME")!)).first! }),
            nameTexts = names.map{ parse!.nodeString($0) }
        //print(nameTexts)
        #expect(nameTexts == ["tag1","tag:2","tag-3"])
    }

    @Test func backtracking() {
        let grammar = PEMachine("""
                   START <- PAT1 / PAT2
                   PAT1  <- HELLO ' One'
                   PAT2  <- HELLO ' Two'
                   HELLO <- 'Hello'
            """)!,
            text = "Hello Two",
            parse = grammar.parse("START", text).succeeded()
        #expect(parse!.endIndex == text.endIndex)
        //parse!.tree.printTree(symbols: grammar.symbols)
        let pat = Array(parse!.tree.childIndices(parse!.tree.root)!)
        #expect(pat.count == 1)
    }

    @Test func backtrackingTree() {
        let grammar = PEMachine("""
            S <- A? B (A B)* A
            A <- 'a'
            B <- 'b'
            """)!,
            text = "ba",
            parse = grammar.parse("S", text).succeeded()
        #expect(parse!.endIndex == text.endIndex)
        //parse!.tree.printTree(symbols: grammar.symbols)
        let s = Array(parse!.tree.childIndices(parse!.tree.root)!)
        #expect(s.count == 2)
    }

}
