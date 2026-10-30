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

nonisolated(unsafe) public let chpegParse = PEMachine<chpegSymbol>(grammar: chpegGrammar)

extension PEMachine.Builder {

    public init?(_ source: String, trace: Bool=false) where Symbol == PENamedSymbol {
        let mr = chpegParse.parse(.Grammar, source, trace: trace)
        switch mr {
        case let .success(success):
            if success.endIndex == success.text.endIndex {
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

    typealias ParseResult = PEMachine<chpegSymbol>.ParseResult.Success

    init(_ parse: ParseResult)  where Symbol == PENamedSymbol {
        program = []
        //parse.printTree()
        //    Grammar     {S} <- S Definition+ !.
        let defSyms = parse.rootVisit.mapChildren { def in
            //    Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
            //def[0].string
            def[.Identifier]!.string
        }
        //print(defSyms)
        symbols = defSyms.indices.map { PENamedSymbol(rawValue: $0,
                                                      name: defSyms[$0] ) }
        start = [PEMachine.Program.Index](repeating: -1, count: defSyms.count)
        ignore = [Bool](repeating: false, count: defSyms.count)
        errors = []
        //    Grammar     {S} <- S Definition+ !.
        let symbolDict = [String:PENamedSymbol](uniqueKeysWithValues:
                                                    symbols.indices.map { ( symbols[$0].name,
                                                                            symbols[$0] ) } )
        parse.rootVisit.visitChildren { def in
            compile(def, symbolDict)
        }

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

    private mutating func compile(_ e: ParseResult.Visit, _ symbols: [String: PENamedSymbol]) {
        switch e.symbol {
        case .Definition:
            //    Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
            let id = e[.Identifier]!.string,
                idSymRaw: Int = symbols[id]!.rawValue
            if let opt = e[.Options] {
                //    Options     { } <- [A-Za-z]*
                let opts = opt.string
                if opts.contains("I") {
                    ignore[idSymRaw] = true
                }
            } else if id.first == "_" {
                ignore[idSymRaw] = true
            }
            start[idSymRaw] = program.count
            compile(e[.Choice]!, symbols)
            program.append(.ret)
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
            var prev: ParseResult.Visit?,
                joins = [PEMachine.Program.Index]()
            e.visitChildren { alt in
                if let prev {
                    let a = dummy()
                    compile(prev, symbols)
                    joins.append(dummy())
                    place(a, .alt(program.endIndex))
                }
                prev = alt
            }
            if let prev {
                compile(prev, symbols)
            }
            joins.forEach { place($0, .commit(program.endIndex)) }
        case .Sequence:
            //    Sequence    { } <- Predicate+
            //
            // E F G
            //
            //          E
            //          F
            //          G
            e.visitChildren { compile($0, symbols) }
        case .Predicate:
            //    Predicate   { } <- (PredOp S)? Repeat
            let rep = e[.Repeat]!
            if let op = e[.PredOp] {
                //    PredOp      {L} <- [&!]
                switch op.string {
                case "&":
                    // &E:
                    //      alt f
                    //      E
                    //      back s
                    //  f:  fail
                    //  s:
                    let a = dummy()
                    compile(rep, symbols)
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
                    compile(rep, symbols)
                    program.append(.fail2)
                    place(p, .alt(program.endIndex))
                default:
                    assertionFailure("Predicate operator found \(op.string.debugDescription)")
                }
            } else {
                compile(rep, symbols)
            }
        case .Repeat:
            //    Repeat      { } <- Primary (RepOp S)?
            let prim = e[.Primary]!
            if let op = e[.RepOp] {
                //    RepOp       {L} <- [*+?]
                switch op.string {
                case "*":
                    if let chrClass = prim[.CharClass] {
                        let ranges = charRanges(chrClass)
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
                    compile(prim, symbols)
                    program.append(.rep(r))
                    place(a, .alt(program.endIndex))
                case "+":
                    if let chrClass = prim[.CharClass] {
                        let ranges = charRanges(chrClass)
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
                    compile(prim, symbols)
                    let a = dummy()
                    let r = program.endIndex
                    compile(prim, symbols)
                    program.append(.rep(r))
                    place(a, .alt(program.endIndex))
                case "?":
                    // E?:
                    //      alt a
                    //      E
                    //      commit a
                    //  a:
                    let a = dummy()
                    compile(prim, symbols)
                    let join = dummy()
                    place(join, .commit(program.endIndex))
                    place(a, .alt(program.endIndex))
                default:
                    assertionFailure("Repeat operator found \(op.string.debugDescription)")
                }
            } else {
                compile(prim, symbols)
            }
        case .Primary:
            //    Primary     { } <- Identifier S ![{<]
            //                     / '(' S Choice ')' S
            //                     / Literal S
            //                     / CharClass S
            //                     / Dot S
            let p = e[0]
            switch p.symbol {
            case .Identifier:
                //    Identifier  {L} <- [a-zA-Z_][a-zA-Z_0-9]*
                if let sym = symbols[p.string] {
                    program.append(.call(sym.rawValue))
                } else {
                    errors.append("Undefined symbol \(p.string)")
                }
            case .Choice:
                return compile(p, symbols)
            case .Literal:
                //    Literal     {S} <- ['] (!['] Char)* [']
                //                     / ["] (!["] Char)* ["]
                let chars = p.mapChildren(.Char) { char($0) }
                if chars.count == 1 {
                    program.append(.chr(PEMachineCore.uniChar(chars.first!)))
                } else if chars.count > 1 {
                    program.append(.lit(PEMachineCore.uniChar(chars.first!),
                                        PEMachineCore.uniText(String(chars.dropFirst()))))
                } else {
                    // empty
                }
            case .CharClass:
                //    CharClass   {S} <- '[' (!']' CharRange)+ ']'
                let ranges = p.mapChildren(.CharRange, calling: range)
                if ranges.isEmpty {
                    program.append(.fail)
                } else if ranges.count == 1 {
                    program.append(.range(ranges.first!.lowerBound, ranges.first!.upperBound))
                } else {
                    let bitset = rangeBitSet(ranges)
                    program.append(bitset.words.count == 1 ? .chrset1(bitset.words[0]) : .chrset(bitset))
                /*
                } else if ranges.allSatisfy({ $0.lowerBound == $0.upperBound }) {
                    let chrs = ranges.map{ Unicode.UTF16.CodeUnit($0.lowerBound) }
                    let cs = String(validating: chrs, as: UTF16.self)!
                 program.append(.chrs(PEMachineCore.uniText(cs)))
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
                */
                }
            case .Dot:
                //    Dot         {L} <- '.'
                program.append(.any1)
            default:
                fatalError("Primary unknown \(p.symbol)")
            }
        default:
            assertionFailure("\(e.symbol) should not be visited")
        }
    }

    private func charRanges(_ e: ParseResult.Visit)->[ClosedRange<PEMachine.UniText.Element>] {
        assert(e.symbol == .CharClass)
        return e.mapChildren(calling: range)
    }

    private func rangeBitSet(_ ranges: [ClosedRange<PEMachine.UniText.Element>]) -> BitSet {
        return BitSet(ranges.map({ UInt32($0.lowerBound)...UInt32($0.upperBound) }))
    }

    private func char(_ e: ParseResult.Visit)->Character {
        //    Char        { } <- EscChar / OctChar / PlainChar
        let char = e[0]
        switch char.symbol {
        case .EscChar:
            //    EscChar     {L} <- '\\' [nrt'"\[\]\\]
            let ec = char.string.dropFirst().first!
            return switch ec {
            case "n": "\n"
            case "r": "\r"
            case "t": "\t"
            case "'": "'"
            case "\"": "\""
            case "[": "["
            case "]": "]"
            case "\\": "\\"
            default:
                fatalError("EscapeChar unexpected \(ec.debugDescription)")
            }
        case .OctChar:
            //    OctChar     {L} <- '\\' [0-3][0-7][0-7]
            //                     / '\\' [0-7][0-7]?
            let digits: [UInt8] = char.string.dropFirst().map { $0.asciiValue! -
                Character("0").asciiValue! },
                octVal: UInt8 = digits.reduce(0) { v, d in v << 3 + d }
            return Character(UnicodeScalar(octVal))
        case .PlainChar:
            //    PlainChar   {L} <- !'\\' .
            return char.string.first!
        default:
            fatalError("Char unexpected symbol \(char.symbol)")
        }
    }

    private func range(_ e: ParseResult.Visit)->ClosedRange<PEMachine.UniText.Element> {
        //    CharRange   { } <- Char '-' !']' Char / Char
        let chars = e.mapChildren(.Char) { PEMachineCore.uniChar(char($0)) }
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
