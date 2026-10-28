//
//  PEParser+chpeg.swift
//  PEGHighlight
//
//  Created by Andy Hooper on 2026-10-03.
//

fileprivate extension PEParser.Tree {
    func nodeSymbol(_ ti: Index)->chpegSymbol {
        chpegSymbol(rawValue: nodes[ti].identifier)!
    }
}
extension PEParser {
    
    public init?(source: String) {
        let parse = PEParser.chpeg.parse(chpegSymbol.Grammar, source)
        switch parse {
        case let .success(success):
            self.init(success)
        case let .failure(failure):
            print("grammar syntax error")
            /*TODO: .*/
            return nil
        }
    }
    
    func printRules() {
        self.symbols.indices.forEach { si in
            print()
            print(si, self.symbols[si], "=", self.rules[si].description)
        }
    }
    
    init(_ parse: PEParser.Result<chpegSymbol>.Success) {
        //parse.tree.printTree(symbols: parse.symbols)
        let defSyms = [Tree.Index](parse.tree.childIndices(parse.tree.root)!).compactMap { di in
            if parse.tree[di].has(chpegSymbol.Definition) {
                var defi = parse.tree.childIndices(di)!
                return parse.nodeString(defi.next()!)
            } else { return nil }
        }
        //print(defSyms)
        let symbols = [String: NamedSymbol](uniqueKeysWithValues: defSyms.indices.map {
                                                (defSyms[$0],
                                                 NamedSymbol(rawValue: $0, name: defSyms[$0])) })
        let build = Builder(parse: parse,
                            symbols: symbols)
        self.init(symbols: defSyms, ignore: build.ignore, rules: build.rules)
        //printRules()
    }
    
    public struct NamedSymbol: Sendable, RawRepresentable, Hashable, CustomStringConvertible {
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
        public var description: String { "\(name)(\(rawValue))" }
    }
    
    struct Builder {
        typealias Result = PEParser.Result<chpegSymbol>
        let parse: Result.Success
        let symbols: [String: NamedSymbol]
        var rules: [Op]
        var ignore: [Bool]
        
        init(parse: Result.Success, symbols:[String: NamedSymbol]) {
            self.parse = parse
            self.symbols = symbols
            self.rules = [Op](repeating: Fail(), count: symbols.count)
            self.ignore = [Bool](repeating: false, count: symbols.count)
            //    Grammar     {S} <- S Definition+ !.
            parse.rootContext.visitChildren { def in
                //    Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
                let id = def[.Identifier]!.string,
                    idSymRaw: Int = symbols[id]!.rawValue
                if let opt = def[.Options] {
                    //    Options     { } <- [A-Za-z]*
                    let opts = opt.string
                    if opts.contains("I") {
                        ignore[idSymRaw] = true
                    }
                } else if id.first == "_" {
                    ignore[idSymRaw] = true
                }
                rules[idSymRaw] = compile(def[.Choice]!)
            }
        }
        
        func compile(_ e: Result.Context)->Op {
            switch e.symbol {
            case .Choice:
                // TODO: optimize for keywords (all Sequences are Literal)
                let alt = e.mapChildren(calling: compile)
                return (alt.count == 1) ? alt.first!
                                        : Alt(alt)
            case .Sequence:
                //    Sequence    { } <- Predicate+
                let seq = e.mapChildren(calling: compile)
                return (seq.count == 1) ? seq.first!
                                        : Seq(seq)
            case .Predicate:
                //    Predicate   { } <- (PredOp S)? Repeat
                let pred = compile(e[.Repeat]!)
                if let op = e[.PredOp] {
                    //    PredOp      {L} <- [&!]
                    switch op.string {
                    case "&":
                        return Pred(pred)
                    case "!":
                        return Not(pred)
                    default:
                        fatalError("Predicate operator unknown \(e.string.debugDescription)")
                    }
                } else {
                    return pred
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
                            return (bitset.words.count == 1) ? SpanSet1(bitset.words[0]) : SpanSet(bitset)
                        }
                        return Rep(compile(prim))
                    case "+":
                        if let chrClass = prim[.CharClass] {
                            let ranges = charRanges(chrClass)
                            let bitset = rangeBitSet(ranges)
                            //print("repeat+", ranges, bitset)
                            return Seq((bitset.words.count == 1) ? ChrSet1(bitset.words[0]) : ChrSet(bitset),
                                       (bitset.words.count == 1) ? SpanSet1(bitset.words[0]) : SpanSet(bitset))
                        }
                        return Rep1(compile(prim))
                    case "?":
                        return Opt(compile(prim))
                    default:
                        fatalError("Repeat operator unknown \(op.string.debugDescription)")
                    }
                } else {
                    return compile(prim)
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
                        return Ref(sym.rawValue)
                    } else {
                        fatalError("Undefined symbol \(p.string)")
                    }
                case .Choice:
                    return compile(p)
                case .Literal:
                    //    Literal     {S} <- ['] (!['] Char)* [']
                    //                     / ["] (!["] Char)* ["]
                    let chars = p.mapChildren(.Char) { char($0) }
                    if chars.count == 1 {
                        return Chr(chars.first!)
                    } else if chars.count > 1 {
                        return Lit(String(chars))
                    } else {
                        return Empty()
                    }
                case .CharClass:
                    //    CharClass   {S} <- '[' (!']' CharRange)+ ']'
                    let ranges = p.mapChildren(.CharRange, calling: range)
                    if ranges.isEmpty {
                        return Fail()
                    } else if ranges.count == 1 {
                        return ChrRange(ranges.first!.lowerBound, ranges.first!.upperBound)
                    } else {
                        let bitset = rangeBitSet(ranges)
                        return (bitset.words.count == 1) ? ChrSet1(bitset.words[0]) : ChrSet(bitset)
                    /*
                    } else if ranges.allSatisfy({ $0.lowerBound == $0.upperBound }) {
                        let chrs = ranges.map{ Unicode.UTF16.CodeUnit($0.lowerBound) }
                        let cs = String(validating: chrs, as: UTF16.self)!
                        return Chrs(cs)
                    } else {
                        // E / F / G:
                        return Alt(ranges.map { ChrRange($0.lowerBound, $0.upperBound) })
                     */
                    }
                case .Dot:
                    //    Dot         {L} <- '.'
                    return Any1()
                default:
                    fatalError("Primary unknown \(p.symbol)")
                }
            default:
                fatalError("\(e.symbol) should not be visited")
            }
        }
        
        private func charRanges(_ e: Result.Context)->[ClosedRange<UniText.Element>] {
            assert(e.symbol == .CharClass)
            return e.mapChildren(calling: range)
        }
        
        private func rangeBitSet(_ ranges: [ClosedRange<UniText.Element>]) -> BitSet {
            return BitSet(ranges.map({ UInt32($0.lowerBound)...UInt32($0.upperBound) }))
        }
        
        private func char(_ e: Result.Context)->Character {
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
        
        private func range(_ e: Result.Context)->ClosedRange<UniText.Element> {
            //    CharRange   { } <- Char '-' !']' Char / Char
            let chars = e.mapChildren(.Char) { uniChar(char($0)) }
            if chars.count == 1 {
                return chars.first!...chars.first!
            } else {
                return chars.first!...chars.dropFirst().first!
            }
        }
    }
}
