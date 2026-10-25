//
//  PEParser.swift
//  PEG
//
//  Created by Andy Hooper on 2026-10-03.
//

public struct PEParser {
    
    // Generics interface defined separately for better chance at optimization
    
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
    let symbols: [String]
    let ignore: [Bool]
    
    // PEG backtracking discards many parse tree nodes, so there is benefit in
    // minimizing their construction cost.
    public typealias Tree = LinearTree<SymbolRaw, Range<UniText.Index>>
    
    struct State {
        struct Call {
            let symRaw: SymbolRaw,
                index: UniText.Index,
                tree: Tree.Index
        }
        struct Fail {
            let i: UniText.Index,
                stack: ArraySlice<Call>
        }
        var tree: Tree
        var callNest: Int
        var callStack: [Call]
        var furthestFail: Fail?
    }
    
    class Op: CustomStringConvertible {
        func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State)->UniText.Index? {
            fatalError("Op parse must be overridden")
        }
        internal func linkRefs(_ p: PEParser) {
        }
        var description: String { "Op description must be overridden" }
    }
    
    let rules: [Op]
    
    init(symbols: [String], rules: [Op]) {
        precondition(symbols.count == rules.count)
        self.symbols = symbols
        self.ignore = symbols.map { $0.starts(with: "_")}
        self.rules = rules
        for r in self.rules.indices {
            self.rules[r].linkRefs(self)
        }
    }
    
    init(symbols: [String], ignore: [Bool], rules: [Op]) {
        precondition(symbols.count == rules.count)
        precondition(symbols.count == ignore.count)
        self.symbols = symbols
        self.ignore = ignore
        self.rules = rules
        for r in self.rules.indices {
            self.rules[r].linkRefs(self)
        }
    }

    class Seq: Op {
        let seq: [Op]
        init(_ seq: Op...) {
            self.seq = seq
        }
        init(_ seq: [Op]) {
            self.seq = seq
        }
        override func linkRefs(_ p: PEParser) {
            seq.forEach { $0.linkRefs(p) }
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            var j = i
            for s in seq {
                if let k = s.parse(t, j, &res) {
                    j = k
                } else {
                    //print(j, "fail seq")
                    return nil
                }
            }
            //print(i, "seq", j)
            return j
        }
        override var description: String { "Seq(\(seq.map({ $0.description }).joined(separator: ", ")))" }
    }
    
    class Alt: Op {
        let alt: [Op]
        init(_ alt: Op...) {
            self.alt = alt
        }
        init(_ alt: [Op]) {
            self.alt = alt
        }
        override func linkRefs(_ p: PEParser) {
            alt.forEach { $0.linkRefs(p) }
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            for a in alt {
                if let k = a.parse(t, i, &res) {
                    //print(i, "alt", k)
                    return k
                }
            }
            //print(i, "fail alt")
            return nil
        }
        override var description: String { "Alt(\(alt.map({ $0.description }).joined(separator: ", ")))" }
    }
    
    class Rep: Op {
        let rep: Op
        init(_ rep: Op) {
            self.rep = rep
        }
        override func linkRefs(_ p: PEParser) {
            rep.linkRefs(p)
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            var j = i
            while let k = rep.parse(t, j, &res) {
                j = k
            }
            //print(i, "rep", j)
            return j
        }
        override var description: String { "Rep(\(rep.description))" }
    }
    
    class Rep1: Op {
        let rep: Op
        init(_ rep: Op) {
            self.rep = rep
        }
        override func linkRefs(_ p: PEParser) {
            rep.linkRefs(p)
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            var j = i
            if let k = rep.parse(t, j, &res) {
                j = k
            } else {
                //print(i, "fail rep1")
                return nil
            }
            while let k = rep.parse(t, j, &res) {
                j = k
            }
            //print(i, "rep1", j)
            return j
        }
        override var description: String { "Rep1(\(rep.description))" }
    }
    
    class Opt: Op {
        let opt: Op
        init(_ opt: Op) {
            self.opt = opt
        }
        override func linkRefs(_ p: PEParser) {
            opt.linkRefs(p)
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if let k = opt.parse(t, i, &res) {
                //print(i, "opt", k)
                return k
            }
            //print(i, "opt")
            return i
        }
        override var description: String { "Opt(\(opt.description))" }
    }
    
    class Pred: Op {
        let pred: Op
        init(_ pred: Op) {
            self.pred = pred
        }
        override func linkRefs(_ p: PEParser) {
            pred.linkRefs(p)
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if let _ = pred.parse(t, i, &res) {
                //print(i, "pred")
                return i
            }
            //print(i, "fail pred")
            return nil
        }
        override var description: String { "Pred(\(pred.description))" }
    }
    
    class Not: Op {
        let not: Op
        init(_ not: Op) {
            self.not = not
        }
        override func linkRefs(_ p: PEParser) {
            not.linkRefs(p)
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if let _ = not.parse(t, i, &res) {
                //print(i, "fail not")
                return nil
            }
            //print(i, "not")
            return i
        }
        override var description: String { "Not(\(not.description))" }
    }
    
    class Chr: Op {
        let chr: UniText.Element
        init(_ chr: Character) {
            self.chr = PEParser.uniText(chr)
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if i < t.endIndex,
               t[i] == chr {
                let k = t.index(after: i)
                //print(i, "chr", k)
                return k
            }
            //print(i, "fail chr")
            return nil
        }
        override var description: String { "Chr(\(Character(UnicodeScalar(chr)!).debugDescription))" }
    }
    
    class Lit: Op {
        let first: UniText.Element, rest: UniText
        init(_ lit: String) {
            let litt = uniText(lit)
            self.first = litt.first!
            self.rest = UniText(litt.dropFirst())
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if i < t.endIndex,
               t[i] == first,
               t.suffix(from: t.index(after: i)).starts(with: rest) {
                let k = t.index(i, offsetBy: rest.count+1)
                //print(i, "lit", k)
                return k
            }
            //print(i, "fail lit")
            return nil
        }
        override var description: String { "Lit(\((PEParser.uniString(first)+PEParser.uniString(rest)).debugDescription))" }
    }
    #if false
    class Chrs: Op {
        let chrs: UniText
        init(_ chrs: String) {
            self.chrs = PEParser.uniText(chrs)
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout Res) -> UniText.Index? {
            if i < t.endIndex,
               chrs.contains(t[i]) {
                let k = t.index(after: i)
                //print(i, "chrs", k)
                return k
            }
            //print(i, "fail chrs")
            return nil
        }
        override var description: String { "Chrs(\(PEParser.uniString(chrs).description))" }
    }
    #endif
    
    class ChrRange: Op {
        let chrr: ClosedRange<UniText.Element>
        init(_ lower: Character, _ upper: Character) {
            self.chrr = PEParser.uniText(lower)...PEParser.uniText(upper)
        }
        init(_ lower: UniText.Element, _ upper: UniText.Element) {
            self.chrr = lower...upper
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if i < t.endIndex,
               chrr.contains(t[i]) {
                let k = t.index(after: i)
                //print(i, "chrr", k)
                return k
            }
            //print(i, "fail chrr")
            return nil
        }
        override var description: String { "ChrRange(\(String(chrr.lowerBound).description), \(String(chrr.upperBound).description))" }
    }
    
    class ChrSet: Op {
        let chrset: BitSet
        init(_ chrset: BitSet) {
            self.chrset = chrset
        }
        init(_ chrset: String) {
            self.chrset = BitSet([UInt32](uniText(chrset).map{UInt32($0)}))
        }
        init(_ chrset: ClosedRange<Character>...) {
            self.chrset = BitSet([ClosedRange<UInt32>](chrset.map{ UInt32( uniText($0.lowerBound))...UInt32(uniText($0.upperBound)) }))
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if i < t.endIndex,
               chrset.contains(UInt32(t[i])) {
                let k = t.index(after: i)
                //print(i, "chrset", k)
                return k
            }
            //print(i, "fail chrset")
            return nil
        }
        override var description: String { "ChrSet(\(chrset.description))" }
    }
    
    class ChrSet1: Op {
        let word: BitSet.Word
        init(_ word: BitSet.Word) {
            self.word = word
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if i < t.endIndex,
               BitSet.wordContains(word, UInt32(t[i])) {
                let k = t.index(after: i)
                //print(i, "chrset1", k)
                return k
            }
            //print(i, "fail chrset1")
            return nil
        }
        override var description: String { "ChrSet1(0x"+String(word, radix: 16, uppercase: true)+")" }
    }
    
    class SpanSet: Op {
        let spanset: BitSet
        init(_ spanset: BitSet) {
            self.spanset = spanset
        }
        init(_ spanset: String) {
            self.spanset = BitSet([UInt32](uniText(spanset).map{UInt32($0)}))
        }
        init(_ spanset: ClosedRange<Character>...) {
            self.spanset = BitSet([ClosedRange<UInt32>](spanset.map{ UInt32( uniText($0.lowerBound))...UInt32(uniText($0.upperBound)) }))
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            var k = i
            while k < t.endIndex,
                  spanset.contains(UInt32(t[k])) {
                k = t.index(after: k)
            }
            //print(i, "spanset", k)
            return k
        }
        override var description: String { "SpanSet(\(spanset.description))" }
    }
    
    class SpanSet1: Op {
        let word: BitSet.Word
        init(_ word: BitSet.Word) {
            self.word = word
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            var k = i
            while k < t.endIndex,
                  BitSet.wordContains(word, UInt32(t[k])) {
                k = t.index(after: k)
            }
            //print(i, "spanset1", k)
            return k
        }
        override var description: String { "SpanSet1(0x"+String(word, radix: 16, uppercase: true)+")" }
    }
    
    class Any1: Op {
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            if i < t.endIndex {
                let k = t.index(after: i)
                //print(i, "any", k)
                return k
            }
            //print(i, "fail any")
            return nil
        }
        override var description: String { "Any1()" }
    }
    
    class Ref: Op {
        let ref: SymbolRaw
        var op: Op, ignore: Bool
        init(_ ref: SymbolRaw) {
            self.ref = ref
            self.op = Op()
            self.ignore = false
        }
        override func linkRefs(_ p: PEParser) {
            op = p.rules[ref]
            ignore = p.ignore[ref]
        }
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            //print(i, "ref", ref)
            let mark = res.tree.mark
            #if DEBUG
            if res.callNest+1 >= res.callStack.count {
                res.callStack.append(State.Call(symRaw: ref, index: i, tree: mark))
            } else {
                res.callStack[res.callNest] = State.Call(symRaw: ref, index: i, tree: mark)
            }
            #endif
            res.callNest += 1
            if let r = op.parse(t, i, &res) {
                if !ignore {
                    //print(i, parser!.symbols[ref], r)
                    res.tree.end(ref, mark, i..<r)
                }
                res.callNest -= 1
                return r
            } else {
                #if DEBUG
                if !ignore,
                   res.furthestFail == nil || res.furthestFail!.i < i {
                    res.furthestFail = State.Fail(i: i, stack: res.callStack[0...res.callNest])
                }
                #endif
                res.callNest -= 1
                res.tree.discard(mark)
                return nil
            }
        }
        override var description: String { "Ref(\(ref))" }
    }
    
    class Fail: Op {
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            nil
        }
        override var description: String { "Fail()" }
    }
    
    class Empty: Op {
        override func parse(_ t: UniText, _ i: UniText.Index, _ res: inout State) -> UniText.Index? {
            i
        }
        override var description: String { "Empty()" }
    }
    
}
