//
//  main.swift
//  tryFunc
//
//  Created by Andy Hooper on 2026-10-22.
//

public struct PEGFun {
    
    //  UTF16 is used for text elements to reduce the size of structures
    //  containing them, to avoid repeated decoding of varying length elements,
    //  and to match the representation in NSAttributedString for  editors.
    
    public typealias UniText = Array<Unicode.UTF16.CodeUnit>
    // Array seems to have a slight performance advantage over ContiguousArray
    internal static func uniText(_ s: String)->UniText { UniText(s.utf16) }
    internal static func uniText(_ c: Character)->UniText.Element { c.utf16.first! }
    internal static func uniString(_ t: UniText)->String { String(validating: t, as: Unicode.UTF16.self)! }
    internal static func uniString(_ c: UniText.Element)->String { String(UnicodeScalar(c)!) }
    
    public typealias SymbolRaw = Int
    public let symbols: [String]
    let ignore: [Bool]
    typealias Op = @Sendable(inout PEGFun, UniText.Index)->UniText.Index?
    let def: [Op]
    let text: UniText
    
    // PEG backtracking discards many parse tree nodes, so there is benefit in
    // minimizing their construction cost.
    public typealias Tree = LinearTree<SymbolRaw, Range<UniText.Index>>
    var tree: Tree
    struct Call {
        let symRaw: SymbolRaw,
            index: UniText.Index,
            tree: Tree.Index
    }
    struct Fail {
        let i: UniText.Index,
            stack: ArraySlice<Call>
    }
    var callNest: Int
    var callStack: [Call]
    var furthestFail: Fail?
   
    static func lit(_ s: String)->Op {
        let st = uniText(s), first = st.first!, rest = st.dropFirst()
        if rest.isEmpty {
            return { p, i in
                if i < p.text.endIndex, p.text[i] == first {
                    return p.text.index(after: i)
                } else {
                    return nil
                }
            }
        }
        return { p, i in
            if i < p.text.endIndex, p.text[i...].starts(with: st) {
                return p.text.index(i, offsetBy: s.count)
            } else {
                return nil
            }
        }
    }
    
    static func `any`(_ n: Int)->Op {
        return { p, i in
            if i < p.text.endIndex,
               let k = p.text.index(i, offsetBy: n, limitedBy: p.text.endIndex) {
                return k
            } else {
                return nil
            }
        }
    }
    
    static func chrs(_ s: String)->Op {
        if s.isEmpty {
            return { p, i in nil }
        }
        let st = uniText(s)
        return { p, i in
            if i < p.text.endIndex, st.contains(p.text[i]) {
                return p.text.index(after: i)
            } else {
                return nil
            }
        }
    }
    
    static func chrs(_ s: BitSet)->Op {
        if s.words.count == 1 {
            let word = s.words.first!
            return { p, i in
                if i < p.text.endIndex,
                   BitSet.wordContains(word, UInt32(p.text[i])) {
                    return p.text.index(after: i)
                } else {
                    return nil
                }
            }
        } else {
            return { p, i in
                if i < p.text.endIndex,
                   s.contains(UInt32(p.text[i])) {
                    return p.text.index(after: i)
                } else {
                    return nil
                }
            }
        }
    }
    
    static func span(_ s: BitSet)->Op {
        if s.words.count == 1 {
            let word = s.words.first!
            return { p, i in
                var k = i
                while k < p.text.endIndex,
                      BitSet.wordContains(word, UInt32(p.text[k])) {
                    k = p.text.index(after: k)
                }
                return k
            }
        } else {
            return { p, i in
                var k = i
                while k < p.text.endIndex,
                      s.contains(UInt32(p.text[k])) {
                    k = p.text.index(after: k)
                }
                return k
            }
        }
    }
    
    static func range(_ c: UniText.Element, _ d: UniText.Element)->Op {
        return { p, i in
            if i < p.text.endIndex, p.text[i] >= c, p.text[i] <= d {
                return p.text.index(after: i)
            } else {
                return nil
            }
        }
    }
    
    static func range(_ c: Character, _ d: Character)->Op {
        return range(uniText(c), uniText(d))
    }
    
    static func call(_ sRaw: SymbolRaw)->Op {
        return { p, i in
            let mark = p.tree.mark
#if DEBUG
            if p.callNest+1 >= p.callStack.count {
                p.callStack.append(Call(symRaw: sRaw, index: i, tree: mark))
            } else {
                p.callStack[p.callNest] = Call(symRaw: sRaw, index: i, tree: mark)
            }
#endif
            p.callNest += 1
            if let k = p.def[sRaw](&p,i) {
                if !p.ignore[sRaw] {
                    //print(i, k, s, string(p.t[i..<k]).debugDescription)
                    p.tree.end(sRaw, mark, i..<k)
                }
                p.callNest -= 1
                return k
            } else {
#if DEBUG
                if !p.ignore[sRaw],
                   p.furthestFail == nil || p.furthestFail!.i < i {
                    p.furthestFail = Fail(i: i, stack: p.callStack[0..<p.callNest])
                }
#endif
                p.callNest -= 1
                p.tree.discard(mark)
                return nil
            }
        }
    }
    
    static func seq(_ ops: [Op])->Op {
        return { p, i in
            var j = i
            for op in ops {
                if let k = op(&p,j) {
                    j = k
                } else {
                    return nil
                }
            }
            return j
        }
    }
    
    static func alt(_ ops: [Op])->Op {
        return { p, i in
            for op in ops {
                if let k = op(&p,i) {
                    return k
                }
            }
            return nil
        }
    }
    
    static func rep(_ op: @escaping Op)->Op {
        return { p, i in
            var j = i
            while let k = op(&p,j) {
                j = k
            }
            return j
        }
    }
    
    static func rep1(_ op: @escaping Op)->Op {
        return { p, i in
            if var j = op(&p,i) {
                while let k = op(&p,j) {
                    j = k
                }
                return j
            } else {
                return nil
            }
        }
    }
    
    static func opt(_ op: @escaping Op)->Op {
        return { p, i in
            if let j = op(&p,i) {
                return j
            } else {
                return i
            }
        }
    }
    
    static func not(_ op: @escaping Op)->Op {
        return { p, i in
            if let _ = op(&p,i) {
                return nil
            } else {
                return i
            }
        }
    }
    
    static func pred(_ op: @escaping Op)->Op {
        return { p, i in
            if let _ = op(&p,i) {
                return i
            } else {
                return nil
            }
        }
    }
    
    static var dummy: Op {
        { p, i in
            return nil
        }
    }
    
    static func build<Symbol>(_ e: PEMachine<Symbol>.PE)->Op {
        switch e {
        case .any(let n):
            return `any`(n)
        case .lit(let s):
            return lit(s)
        case .chrs(let s):
            return chrs(s)
        case .range(let c, let d):
            return range(c, d)
        case .call(let s):
            return call(s.rawValue)
        case .seq(let s):
            let ops = s.map(build)
            return seq(ops)
        case .alt(let a):
            let ops = a.map(build)
            return alt(ops)
        case .rep(let e):
            let op = build(e)
            return rep(op)
        case .rep1(let e):
            let op = build(e)
            return rep1(op)
        case .opt(let e):
            let op = build(e)
            return opt(op)
        case .not(let e):
            let op = build(e)
            return not(op)
        case .pred(let e):
            let op = build(e)
            return pred(op)
        }
    }
    
    public struct Grammar {
        let symbols: [String],
            ignore: [Bool],
            def: [Op]
    }
    
    public static func grammar<Symbol>(_ g: [Symbol: PEMachine<Symbol>.PE])->Grammar
                         where Symbol: Hashable & RawRepresentable & Sendable,
                               Symbol.RawValue == SymbolRaw,
                               Symbol: CaseIterable {
        let symbols = Symbol.allCases,
            symDesc = symbols.map { String(describing: $0)}
                                            return Grammar(symbols: symDesc,
                                                           ignore: symDesc.map { $0.starts(with: "_") },
                                                           def: symbols.map { PEGFun.build(g[$0]!) })
    }
    
    init(_ grammar: Grammar, _ t: String) {
        self.symbols = grammar.symbols
        self.ignore = grammar.ignore
        self.def = grammar.def
        self.text = PEGFun.uniText(t)
        self.tree = Tree()
        self.callNest = 0
        self.callStack = []
    }
    
    public static func parse<Symbol>(_ grammar: Grammar, _ t: String, _ s: Symbol)->PEParser.Result<Symbol>
                        where Symbol: RawRepresentable,
                              Symbol.RawValue == SymbolRaw,
                              Symbol: CaseIterable {
        var p = PEGFun(grammar, t)
        let m = p.tree.mark, i = p.text.startIndex
        if let k = p.def[s.rawValue](&p,i) {
            //print(i, k, s, string(p.t[i..<k]).debugDescription)
            p.tree.end(s.rawValue, m, i..<k)
            return .success(PEParser.Result<Symbol>.Success(text: p.text,
                                                            endIndex: k,
                                                            tree: p.tree,
                                                            symbols: [Symbol](Symbol.allCases)))
        } else {
            p.tree.discard(m)
            #if DEBUG
            return .failure(PEParser.Result<Symbol>.Failure(text: p.text,
                                                            endIndex: p.text.startIndex,
                                                            stack: p.furthestFail?.stack.map { ($0.symRaw, $0.index )} ?? [],
                                                            symbols: [Symbol](Symbol.allCases)))
            #else
            return .failure(PEParser.Result<Symbol>.Failure())
            #endif
        }
    }

}

fileprivate extension PEGFun.Tree {
    func nodeSymbol(_ ti: Index)->chpegSymbol {
        chpegSymbol(rawValue: nodes[ti].identifier)!
    }
}
extension PEGFun {
    nonisolated(unsafe) static let chpeg = PEGFun.grammar(chpegGrammar)
    public static func grammar(source: String)->Grammar? {
        let r = PEGFun.parse(PEGFun.chpeg, source, chpegSymbol.Grammar)
        switch r {
        case .success(let parse):
            return grammar(parse)
        case .failure(let fail):
            #if DEBUG
            print("grammar syntax error",
                  fail.stack.map { (fail.symbols[$0.0], $0.1) }) //TODO: _
            #else
            print("grammar syntax error")
            #endif
            return nil
        }
    }
    
    static func grammar(_ parse: PEParser.Result<chpegSymbol>.Success)->Grammar {
        //parse.tree.printTree(symbols: parse.symbols)
        let defSyms = [Tree.Index](parse.tree.childIndices(parse.tree.root)!).compactMap { di in
            if parse.tree[di].has(chpegSymbol.Definition) {
                var defi = parse.tree.childIndices(di)!
                return parse.nodeString(defi.next()!)
            } else { return nil }
        }
        let symbols = [String: PEParser.NamedSymbol](uniqueKeysWithValues: defSyms.indices.map {
                                                (defSyms[$0],
                                                 PEParser.NamedSymbol(rawValue: $0, name: defSyms[$0])) })
        var ignore = defSyms.map { $0.starts(with: "_") }
        var defs = [Op](repeating: dummy, count: defSyms.count)
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
            defs[idSymRaw] = compile(def[.Choice]!)
        }
        return Grammar(symbols: defSyms, ignore: ignore, def: defs)
        
        typealias Context = PEParser.Result<chpegSymbol>.Context
        typealias PE = PEMachine<PEParser.NamedSymbol>.PE
        func compile(_ e: Context)->Op {
            switch e.symbol {
            case .Choice:
                // TODO: optimize for keywords (all Sequences are Literal)
                let a = e.mapChildren(calling: compile)
                return (a.count == 1) ? a.first! : alt(a)
            case .Sequence:
                //    Sequence    { } <- Predicate+
                let s = e.mapChildren(calling: compile)
                return (s.count == 1) ? s.first! : seq(s)
            case .Predicate:
                //    Predicate   { } <- (PredOp S)? Repeat
                let p = compile(e[.Repeat]!)
                if let op = e[.PredOp] {
                    //    PredOp      {L} <- [&!]
                    switch op.string {
                    case "&":
                        return pred(p)
                    case "!":
                        return not(p)
                    default:
                        fatalError("Predicate operator unknown \(e.string.debugDescription)")
                    }
                } else {
                    return p
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
                            return span(bitset)
                        }
                        return rep(compile(prim))
                    case "+":
                        if let chrClass = prim[.CharClass] {
                            let ranges = charRanges(chrClass)
                            let bitset = rangeBitSet(ranges)
                            //print("repeat+", ranges, bitset)
                            return seq([chrs(bitset), span(bitset)])
                        }
                        return rep1(compile(prim))
                    case "?":
                        return opt(compile(prim))
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
                        return call(sym.rawValue)
                    } else {
                        fatalError("Undefined symbol \(p.string)")
                    }
                case .Choice:
                    return compile(p)
                case .Literal:
                    //    Literal     {S} <- ['] (!['] Char)* [']
                    //                     / ["] (!["] Char)* ["]
                    let chars = p.mapChildren(.Char) { char($0) }
                    return lit(String(chars))
                case .CharClass:
                    //    CharClass   {S} <- '[' (!']' CharRange)+ ']'
                    let ranges = charRanges(p)
                    if ranges.isEmpty {
                        return chrs("")
                    } else if ranges.count == 1 {
                        return PEGFun.range(ranges.first!.lowerBound, ranges.first!.upperBound)
                    } else {
                        let bitset = rangeBitSet(ranges)
                        return chrs(bitset)
                    }
                case .Dot:
                    //    Dot         {L} <- '.'
                    return `any`(1)
                default:
                    fatalError("Primary unknown \(p.symbol)")
                }
            default:
                fatalError("\(e.symbol) should not be visited")
            }
        }
        
        func charRanges(_ e: Context)->[ClosedRange<UniText.Element>] {
            assert(e.symbol == .CharClass)
            return e.mapChildren(.CharRange, calling: range)
        }
        
        func rangeBitSet(_ ranges: [ClosedRange<UniText.Element>]) -> BitSet {
            return BitSet(ranges.map({ UInt32($0.lowerBound)...UInt32($0.upperBound) }))
        }
        
        func char(_ e: Context)->Character {
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
        
        func range(_ e: Context)->ClosedRange<UniText.Element> {
            //    CharRange   { } <- Char '-' !']' Char / Char
            let chars = e.mapChildren(.Char) { uniText(char($0)) }
            if chars.count == 1 {
                return chars.first!...chars.first!
            } else {
                return chars.first!...chars.dropFirst().first!
            }
        }

    }
    
    public static func parse(_ grammar: Grammar, _ t: String, _ s: String)->PEParser.Result<String> {
        var p = PEGFun(grammar, t)
        let sRaw = p.symbols.firstIndex(of: s)!
        let m = p.tree.mark, i = p.text.startIndex
        if let k = p.def[sRaw](&p,i) {
            //print(i, k, s, string(p.t[i..<k]).debugDescription)
            p.tree.end(sRaw, m, i..<k)
            return .success(PEParser.Result<String>.Success(text: p.text,
                                                            endIndex: k,
                                                            tree: p.tree,
                                                            symbols: p.symbols))
        } else {
            p.tree.discard(m)
            #if DEBUG
            return .failure(PEParser.Result<String>.Failure(text: p.text,
                                                            endIndex: p.text.startIndex,
                                                            stack: p.furthestFail?.stack.map { ($0.symRaw, $0.index )} ?? [],
                                                            symbols: p.symbols))
            #else
            return .failure(PEParser.Result<String>.Failure())
            #endif
        }
    }

}
