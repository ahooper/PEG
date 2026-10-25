//
//  PEMachine+chpeg.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-20.
//

public struct PENamedSymbol: Sendable, RawRepresentable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public typealias RawValue = Int
    public let rawValue: Int
    public let name: String
    public init(rawValue: Int, name: String) {
        self.rawValue = rawValue
        self.name = name
    }
    public init?(rawValue: Int) {
        self.rawValue = rawValue
        self.name = String(rawValue)
    }
    public var description: String { name }
    public var debugDescription: String { "\(name)(\(rawValue))" }
}

public let chpegParse = PEMachine<chpegSymbol>(grammar: chpegGrammar)

extension PEMachine.Builder {

    public init?(_ source: String, trace: Bool=false) where Symbol == PENamedSymbol {
        let mr = chpegParse.parse(.Grammar, source, trace: trace)
        switch mr {
        case let .success(success):
            if success.endIndex == source.endIndex {
                //r.tree.printTree(symbols: r.symbols)
                self.init(success)
                checkLeftRecursion(success)
            } else {
                //TODO: throw
                print("grammar syntax error", success.endIndex)
                return nil
            }
        case let .failure(failure):
            //TODO: throw
            #if DEBUG
            print("grammar syntax error", failure.endIndex)
            failure.printFailure()
            #else
            print("grammar syntax error")
            #endif
            return nil
        }
    }

    init(_ parse: PEMachine<chpegSymbol>.ParseResult.Success)  where Symbol == PENamedSymbol {
        program = []
        //parse.printTree()
        //parse.rootContext.visitChildren { def in
        //    print(def.symbol, def.string)
        //}
//        let defSyms = parse.rootContext.mapChildren { def in
//            //    Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
//            //def[0].string
//            def[.Identifier]!.string
//        }
        let defSyms = [PEMachine.Tree.Index](parse.tree.childIndices(parse.tree.root)!).compactMap { di in
            if parse.tree[di].has(chpegSymbol.Definition) {
                var defi = parse.tree.childIndices(di)!
                let id:String = parse.nodeString(defi.next()!)
                return id
            } else { return nil }
        }
        //print(defSyms)
        symbols = defSyms.indices.map { PENamedSymbol(rawValue: $0,
                                                      name: defSyms[$0] ) }
        start = [PEMachine.Program.Index](repeating: -1, count: defSyms.count)
        ignore = [Bool](repeating: false, count: defSyms.count)
        errors = []
        let symbolDict = [String:PENamedSymbol](uniqueKeysWithValues:
                                                    symbols.indices.map { ( symbols[$0].name,
                                                                            symbols[$0] ) } )
        compile(parse, parse.tree.root, symbolDict)
        let undef = program.compactMap {
            if case let .call(call) = $0,
               start[call] < 0 {
                call
            } else {
                nil
            }
        }
        if !undef.isEmpty { errors.append("Undefined symbol(s) \(undef)") }
    }

    private mutating func compile(_ parse: PEMachine<chpegSymbol>.ParseResult.Success,
                                  _ ti: PEMachine.Tree.Index,
                                  _ symbols: [String: PENamedSymbol]) {
        var children = parse.tree.childIndices(ti)
        switch parse.nodeSymbol(ti) {
        case .Grammar:
            //    Grammar     {S} <- S Definition+ !.
            children!.forEach { compile(parse, $0, symbols) }
        case .Definition:
            //    Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
            if var children,
               let idx = children.opt(chpegSymbol.Identifier) {
                let id = parse.nodeString(idx)
                let idSymRaw: Int = symbols[id]!.rawValue
                if let optx = children.opt(chpegSymbol.Options) {
                    //    Options     { } <- [A-Za-z]*
                    let opts = parse.nodeString(optx)
                    if opts.contains("I") {
                        ignore[idSymRaw] = true
                    }
                } else if id.first == "_" {
                    ignore[idSymRaw] = true
                }
                start[idSymRaw] = program.count
                children.forEach { compile(parse, $0, symbols) }
                program.append(.ret)
            } else {
                assertionFailure("Definition expected Identifier")
            }
        case .Choice:
            // TODO: optimize for keywords (all Sequences are Literal)
            //    Choice      { } <- Sequence ('/' S Sequence)*
            //
            // E / F / G:
            //      alt a1
            //      E
            //      commit c
            //  a1: alt a2
            //      F
            //      commit c
            //  a2:
            //      G
            //  c:
            let alts = [PEMachine<chpegSymbol>.Tree.Index](children!)
            var joins = [PEMachine.Program.Index]()
            alts.dropLast().forEach {
                let a = dummy()
                compile(parse, $0, symbols)
                joins.append(dummy())
                place(a, .alt(program.endIndex))
            }
            compile(parse, alts.last!, symbols)
            joins.forEach { place($0, .commit(program.endIndex)) }
        case .Sequence:
            //    Sequence    { } <- Predicate+
            //
            // E F G
            //
            //          E
            //          F
            //          G
            children!.forEach { compile(parse, $0, symbols) }
        case .Predicate:
            //    Predicate   { } <- (PredOp S)? Repeat
            if var children,
               let opx = children.opt(chpegSymbol.PredOp) {
                //    PredOp      {L} <- [&!]
                let rep = children.next()!
                switch parse.nodeString(opx) {
                case "&":
                    // &E:
                    //      alt f
                    //      E
                    //      back s
                    //  f:  fail
                    //  s:
                    let a = dummy()
                    compile(parse, rep, symbols)
                    let b = dummy()
                    place(a, .alt(program.endIndex))
                    program.append(.fail)
                    place(b, .back(program.endIndex))
                case "!":
                    // !E:
                    //      alt a
                    //      E
                    //      fail2
                    //  a:
                    let p = dummy()
                    compile(parse, rep, symbols)
                    program.append(.fail2)
                    place(p, .alt(program.endIndex))
                default:
                    assertionFailure("Predicate operator found \(parse.nodeString(opx).debugDescription)")
                }
            } else {
                compile(parse, children!.next()!, symbols)
            }
        case .Repeat:
            //    Repeat      { } <- Primary (RepOp S)?
            if var children,
               let prim = children.next() {
                if let opx = children.opt(chpegSymbol.RepOp) {
                    //    RepOp       {L} <- [*+?]
                    switch parse.nodeString(opx) {
                    case "*":
                        if var primx = parse.tree.childIndices(prim),
                           let classx = primx.opt(chpegSymbol.CharClass) {
                            let ranges = charRanges(parse, classx)
                            let bitset = rangeBitSet(ranges)
                            //print("repeat*", ranges, bitset)
                            program.append(bitset.words.count == 1 ? .spanset1(bitset.words[0]) : .spanset(bitset))
                            break
                        }
                        // E*:
                        //      alt a
                        //  r:  E
                        //      rep r
                        //  a:
                        let a = dummy()
                        let r = program.endIndex
                        compile(parse, prim, symbols)
                        program.append(.rep(r))
                        place(a, .alt(program.endIndex))
                    case "+":
                        if var primx = parse.tree.childIndices(prim),
                           let classx = primx.opt(chpegSymbol.CharClass) {
                            let ranges = charRanges(parse, classx)
                            let bitset = rangeBitSet(ranges)
                            //print("repeat+", ranges, bitset)
                            program.append(bitset.words.count == 1 ? .chrset1(bitset.words[0]) : .chrset(bitset))
                            program.append(bitset.words.count == 1 ? .spanset1(bitset.words[0]) : .spanset(bitset))
                            break
                        }
                        // E+:
                        //      E
                        //      alt a
                        //  r:  E
                        //      rep r
                        //  a:
                        compile(parse, prim, symbols)
                        let a = dummy()
                        let r = program.endIndex
                        compile(parse, prim, symbols)
                        program.append(.rep(r))
                        place(a, .alt(program.endIndex))
                    case "?":
                        // E?:
                        //      alt a
                        //      E
                        //      commit a
                        //  a:
                        let a = dummy()
                        compile(parse, prim, symbols)
                        let join = dummy()
                        place(join, .commit(program.endIndex))
                        place(a, .alt(program.endIndex))
                    default:
                        assertionFailure("Repeat operator found \(parse.nodeString(opx).debugDescription)")
                    }
                } else {
                    compile(parse, prim, symbols)
                }
            }
        case .Primary:
            //    Primary     { } <- Identifier S ![{<]
            //                     / '(' S Choice ')' S
            //                     / Literal S
            //                     / CharClass S
            //                     / Dot S
            if var children {
                if let idx = children.opt(chpegSymbol.Identifier) {
                    //    Identifier  {L} <- [a-zA-Z_][a-zA-Z_0-9]*
                    if let sym = symbols[parse.nodeString(idx)] {
                        program.append(.call(sym.rawValue))
                    } else {
                        errors.append("Undefined symbol \(parse.nodeString(idx))")
                    }
                } else if let choicex = children.opt(chpegSymbol.Choice) {
                    compile(parse, choicex, symbols)
                } else if let litx = children.opt(chpegSymbol.Literal) {
                    //    Literal     {S} <- ['] (!['] Char)* [']
                    //                     / ["] (!["] Char)* ["]
                    if let chari = parse.tree.childIndices(litx) {
                        let charx = chari.filter{parse.tree[$0].has(chpegSymbol.Char)}
                        let chars = String(charx.map{char(parse,$0)})
                        if chars.count == 1 {
                            program.append(.chr(PEMachineCore.uc(chars).first!))
                        } else /*if chars.count > 1*/ {
                            program.append(.lit(PEMachineCore.uc(chars.first!),
                                                PEMachineCore.uc(String(chars.dropFirst()))))
                        }
                    } else {
                        // empty
                    }
                } else if let classx = children.opt(chpegSymbol.CharClass) {
                    //    CharClass   {S} <- '[' (!']' CharRange)+ ']'
                    let ranges = charRanges(parse, classx)
                    if ranges.isEmpty {
                        program.append(.fail)
                    } else if ranges.count == 1 {
                        program.append(.range(ranges.first!.lowerBound, ranges.first!.upperBound))
                    } else if true {
                        let bitset = rangeBitSet(ranges)
                        program.append(bitset.words.count == 1 ? .chrset1(bitset.words[0]) : .chrset(bitset))
                    } else if ranges.allSatisfy({ $0.lowerBound == $0.upperBound }) {
                        let chrs = ranges.map{ Unicode.UTF16.CodeUnit($0.lowerBound) }
                        let cs = String(validating: chrs, as: UTF16.self)!
                        program.append(.chrs(PEMachineCore.uc(cs)))
                    } else {
                        // E / F / G:
                        //      alt a1
                        //      E
                        //      commit c
                        //  a1: alt a2
                        //      F
                        //      commit c
                        //  a2:
                        //      G
                        //  c:
                        var joins = [PEMachine.Program.Index]()
                        ranges.dropLast().forEach {
                            let a = dummy()
                            program.append(.range($0.lowerBound, $0.upperBound))
                            joins.append(dummy())
                            place(a, .alt(program.endIndex))
                        }
                        program.append(.range(ranges.last!.lowerBound, ranges.last!.upperBound))
                        joins.forEach { place($0, .commit(program.endIndex)) }
                    }
                } else if let _ = children.opt(chpegSymbol.Dot) {
                    //    Dot         {L} <- '.'
                    program.append(.any1)
                } else {
                    assertionFailure("Primary expected Identifier, Choice, Literal, CharClass or Dot")
                }
            }
        default:
            assertionFailure("\(parse.nodeSymbol(ti)) should not be visited")
        }
    }

    private func charRanges(_ parse: PEMachine<chpegSymbol>.ParseResult.Success,
                            _ ti: PEMachine.Tree.Index)->[ClosedRange<PEMachine.UniChar>] {
        let rangex = parse.tree.childIndices(ti)!.filter{parse.tree[$0].has(chpegSymbol.CharRange)}
        return rangex.map{range(parse,$0)}
    }
    
    private func rangeBitSet(_ ranges: [ClosedRange<PEMachine.UniChar>]) -> BitSet {
        return BitSet(ranges.map({ UInt32($0.lowerBound)...UInt32($0.upperBound) }))
    }

    private func char(_ parse: PEMachine<chpegSymbol>.ParseResult.Success,
                      _ ti: PEMachine.Tree.Index)->Character {
        //    Char        { } <- EscChar / OctChar / PlainChar
        var children = parse.tree.childIndices(ti)!
        let ci = children.next()!
        let s = parse.nodeString(ci)
        switch parse.nodeSymbol(ci) {
        case .EscChar:
            //    EscChar     {L} <- '\\' [nrt'"\[\]\\]
            let ec = s.dropFirst().first!
            switch ec {
            case "n": return "\n"
            case "r": return "\r"
            case "t": return "\t"
            case "'": return "'"
            case "\"": return "\""
            case "[": return "["
            case "]": return "]"
            case "\\": return "\\"
            default:
                assertionFailure("EscapeChar unexpected \(ec.debugDescription)")
                return ec
            }
        case .OctChar:
            //    OctChar     {L} <- '\\' [0-3][0-7][0-7]
            //                     / '\\' [0-7][0-7]?
            let digits: [UInt8] = s.dropFirst().map { $0.asciiValue! -
                                                                Character("0").asciiValue! },
                octVal: UInt8 = digits.reduce(0) { v, d in v << 3 + d }
            return Character(UnicodeScalar(octVal))
        case .PlainChar:
            //    PlainChar   {L} <- !'\\' .
            return s.first!
        default:
            assertionFailure("Char unexpected symbol \(parse.nodeSymbol(ti))")
            return "\u{FFFD}"
        }
    }

    private func range(_ parse: PEMachine<chpegSymbol>.ParseResult.Success,
                       _ ti: PEMachine<chpegSymbol>.Tree.Index)->ClosedRange<PEMachine.UniChar> {
        //    CharRange   { } <- Char '-' !']' Char / Char
        let charx = parse.tree.childIndices(ti)!.filter{parse.tree[$0].has(chpegSymbol.Char)}
        let chars = charx.map{PEMachineCore.uc(char(parse,$0))}
        if chars.count == 1 {
            return chars.first!...chars.first!
        } else {
            return chars.first!...chars.dropFirst().first!
        }
    }

}

extension PEMachine {
    public init?(_ source: String, trace: Bool=false) where Symbol == PENamedSymbol {
        if let build = Builder(source, trace: trace) {
            build.errors.forEach{ print($0) }
            if !build.errors.isEmpty { return nil }
            symbols = build.symbols
            core = PEMachineCore(symbols: symbols.map({$0.name}),
                                 program: build.program,
                                 start: build.start,
                                 ignore: build.ignore)
        } else {
            return nil
        }
    }
}
