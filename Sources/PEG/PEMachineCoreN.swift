//
//  PEMachineCoreN.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-20.
//
//  EXPERIMENT with UniText = NSString to possibly simplify result range mapping
//    Built 2026-10-28, 06:17
//    chpeg_compile: Parse successful.
//    chpeg time 0.044030125 seconds
//    peglib time 0.027481583 seconds -37.6 %
//    text 455620 end 455620 nodes 55419
//    PEMachine time 0.025855625 seconds -41.3 %
//    text 455620 end 455620 nodes 55419
//    PEMachineN time 0.053595333 seconds 21.7 %
//    text 455620 end 455620 nodes 55419
//    PEParser time 0.0275415 seconds -37.4 %
//    text 455620 end 455620 nodes 55419
//    PEGFun time 0.02833325 seconds -35.7 %
//    text 455620 end 455620 nodes 55419
//    pointer machine time 0.019622166 seconds -55.4 %

/*  The parsing machine is closely based on the Lua lpeg machine described
 *  by Ierusalimschy: https://www.inf.puc-rio.br/~roberto/docs/peg.pdf
 *  The state transitions are from Figures 2 and 3.
 */

#if false
#if DEBUG
protocol DebugEquatable: Equatable { }
// Approximate Unicode equality adequate for comparing program instructions
// in testing.
extension String.UTF16View: @retroactive Equatable {
    static public func ==(_ a: String.UTF16View, _ b: String.UTF16View)->Bool {
        a.count == b.count && a.indices.allSatisfy({ a[$0] == b[$0] })
    }
}
#else
protocol DebugEquatable { }
#endif
#endif
import class Foundation.NSString
import struct Foundation.NSRange
import typealias Foundation.unichar
public struct PEMachineCoreN {
    
    // The PEMachine itself is immutable. A separate Builder struct is used to
    // construct the program from a grammar.
    
    // The core is defined separately in hope the compiler will better optimize
    // the 'parse' function.
    
    public typealias Symbols = [String]
    public let symbols: Symbols
    
    // == Text representation ==
    
    //  UTF16 is used for text elements to reduce the size of structures
    //  containing them, to avoid repeated decoding of varying length elements,
    //  and to match the representation in NSAttributedString for  editors.

    public typealias UniText = NSString
    public typealias UniTextIndex = Int
    internal typealias UniChar = unichar
    internal static func uniText(_ s: String)->UniText { UniText(string: s) }
    internal static func uniChar(_ c: Character)->UniChar { c.utf16.first! }
    internal static func uniString(_ t: UniText)->String { String(t) }
    internal static func uniString(_ t: UniText, _ range: Range<UniTextIndex>)->String {
        t.substring(with: NSRange(location: range.lowerBound, length: range.count)) }
    internal static func uniString(_ c: UniChar)->String { String(UnicodeScalar(c)!) }
    
    //  TODO: Codable conformance to enable program save-reload, or is it sufficient
    //  to just load grammars in source form?
    //  https://forums.swift.org/t/why-is-character-not-codable/56178
        
    // == Program instructions ==
    
    typealias Program = [Inst]
    enum Inst: DebugEquatable {
        case any(Int)
        case any1
        case chr(UniChar)
        case lit(UniChar,UniText)
        case chrs(UniText)
        case chrset(BitSet)
        case chrset1(BitSet.Word)
        case span(UniText)
        case spanset(BitSet)
        case spanset1(BitSet.Word)
        case range(UniChar,UniChar) //TODO?: multiple ranges?
        case call(Symbols.Index)
        case alt(Program.Index)
        case commit(Program.Index)
        case rep(Program.Index)
        case back(Program.Index)
        case fail
        case fail2
        case ret
        case _dummy
    }
    let program: Program,
        start: [Program.Index],
        ignore: [Bool]
        
    public func printProgram() {
        for si in symbols.indices {
            print("\(symbols[si])(\(si)):")
            for p in start[si]..<program.endIndex {
                print("  ", p, program[p])
                if case .ret = program[p] { break }
            }
        }
    }

    // == Parsing ==
    
    // Many parse tree nodes are discarded in backtracking, so minimize
    // their construction cost.
    public typealias Tree = LinearTree<Symbols.Index, Range<UniTextIndex>>
    
    #if DEBUG
    struct CallStack {
        let ret: Program.Index,
            index: UniTextIndex,
            tree: Tree.Index
    }
    struct Fail {
        let i: UniTextIndex,
            stack: ArraySlice<CallStack>
    }
    #endif
    
    // Non-generic result in hope of better optimization
    internal enum CoreResult {
        case success(index: UniTextIndex, tree: Tree)
        #if DEBUG
        case failure(Fail)
        #else
        case failure
        #endif
    }
    
    static func contains(_ text: UniText, _ char: UniChar)->Bool {
        (0..<text.length).contains { text.character(at: $0) == char }
//        for i in 0..<text.length { if text.character(at: i) == char { return true }}
//        return false
    }
    
    static func equal(_ text: UniText, _ start: Int, _ other: UniText)->Bool {
        (0..<other.length).allSatisfy { text.character(at: $0+start) == other.character(at: $0) }
    }

    func parse(_ sym: Symbols.Index, _ t: UniText, trace: Bool = false)->CoreResult {
        var i = 0,
            tree = Tree()
        #if DEBUG
        var furthestFail: Fail?
        var callStack: [CallStack] = [] // Simulated call stack
        callStack.reserveCapacity(100)
        #endif
        if case .ret = seq(start[sym], 0) {
            if !ignore[sym] {
                if trace { print(0, i, sym) }
                tree.end(sym, tree.nodes.startIndex, 0..<i)
            }
            return .success(index: i, tree: tree)
        } else {
            #if DEBUG
            if let furthestFail {
                //failReport(t, furthestFail)
                return .failure(furthestFail)
            } else {
                return .failure(Fail(i: 0, stack: []))
            }
            #else
            return .failure
            #endif
        }

        func seq(_ s: Program.Index, _ nest: Int)->Inst {
            // caller is responsible to restore i and tree on failure(->.fail)
            var p = s
            while true {
                if trace { print(i, p, program[p]) }
                switch program[p] {
                case let .any(n):
                    //    ⟨p, i, e, c⟩    Any n, i + n ≤ |S|  ⇒ ⟨p + 1, i + n, e, c⟩
                    //    ⟨p, i, e, c⟩    Any n, i + n > |S|  ⇒ ⟨Fail, i, e, c⟩
                    if i + n < t.length {
                        i += n
                        p += 1
                    } else {
                        return .fail
                    }
                case  .any1:
                    //    ⟨p, i, e, c⟩    Any n, i + n ≤ |S|  ⇒ ⟨p + 1, i + n, e, c⟩
                    //    ⟨p, i, e, c⟩    Any n, i + n > |S|  ⇒ ⟨Fail, i, e, c⟩
                    if i < t.length {
                        i += 1
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chr(chr):
                    //    ⟨p, i, e, c⟩    Char x, S[i] = x    ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Char x, S[i] ≠ x    ⇒ ⟨Fail, i, e, c⟩
                    if i < t.length,
                       t.character(at: i) == chr {
                        i += 1
                        p += 1
                    } else {
                        return .fail
                    }
                case let .lit(first,rest):
                    //    ⟨p, i, e, c⟩    Char x, S[i] = x    ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Char x, S[i] ≠ x    ⇒ ⟨Fail, i, e, c⟩
                    if i+rest.length < t.length,
                       t.character(at: i) == first,
                       Self.equal(t, i+1, rest) {
                        i += rest.length+1
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chrs(chrs):
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∈ X ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∉ X ⇒ ⟨Fail, i, e, c⟩
                    if i < t.length,
                       Self.contains(chrs, t.character(at: i)) {
                        i += 1
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chrset(chrset):
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∈ X ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∉ X ⇒ ⟨Fail, i, e, c⟩
                    if i < t.length,
                       chrset.contains(UInt32(t.character(at: i))) {
                        i += 1
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chrset1(word):
                    if i < t.length,
                       BitSet.wordContains(word, UInt32(t.character(at: i))) {
                        i += 1
                        p += 1
                    } else {
                        return .fail
                    }
                case let .spanset(spanset):
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∈ X    ⇒ ⟨p, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∉ X    ⇒ ⟨p + 1, i, e, c⟩
                    while i < t.length,
                          spanset.contains(UInt32(t.character(at: i))) {
                        i += 1
                    }
                    p += 1
                case let .spanset1(word):
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∈ X    ⇒ ⟨p, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∉ X    ⇒ ⟨p + 1, i, e, c⟩
                    while i < t.length,
                          BitSet.wordContains(word, UInt32(t.character(at: i))) {
                        i += 1
                    }
                    p += 1
                case let .span(span):
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∈ X    ⇒ ⟨p, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∉ X    ⇒ ⟨p + 1, i, e, c⟩
                    while i < t.length,
                          Self.contains(span, t.character(at: i)) {
                        i += 1
                    }
                    p += 1
                case let .range(lower, upper):
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∈ X ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∉ X ⇒ ⟨Fail, i, e, c⟩
                    if i < t.length,
                       lower <= t.character(at: i),
                       t.character(at: i) <= upper {
                        i += 1
                        p += 1
                    } else {
                        return .fail
                    }
                case let .call(call):
                    //    ⟨p, i, e, c⟩    Call l              ⇒ ⟨p + l, i, (p + 1) : e, c⟩
                    let i0 = i, t0 = tree.mark
                    #if DEBUG
                    if nest+1 >= callStack.count {
                        callStack.append(CallStack(ret: p+1, index: i0, tree: t0))
                    } else {
                        callStack[nest] = CallStack(ret: p+1, index: i0, tree: t0)
                    }
                    #endif
                    let r = seq(start[call], nest+1)
                    switch r {
                    case .ret:
                        if !ignore[call] {
                            if trace { print(i0, i, symbols[call]) }
                            tree.end(call, t0, i0..<i)
                        }
                        p += 1
                    case .fail:
                        //               ⟨Fail, i, p : e, c⟩    any                 ⇒ ⟨Fail, i, e, c⟩
                        if trace { print(i0, i, "FAIL", symbols[call]) }
                        #if DEBUG
                        if !ignore[call],
                           furthestFail == nil || furthestFail!.i < i {
                            furthestFail = Fail(i: i, stack: callStack[0...nest])
                        }
                        #endif
                        i = i0; tree.discard(t0)
                        return r
                    default:
                        assertionFailure(".call unexpected seq result \(r)")
                        return r
                    }
                case .ret:
                    //                 ⟨p0, i, p1 : e, c⟩    Return              ⇒ ⟨p1, i, e, c⟩
                    return .ret
                case let .alt(alt):
                    //    ⟨p, i, e, c⟩    Choice l            ⇒ ⟨p + 1, i, (p + l, i, c) : e, c⟩
                    p += 1
                rep:
                    while true {
                        let i1 = i, t1 = tree.mark
                        let r = seq(p, nest)
                        if trace { print(i, ".alt", r) }
                        switch r {
                        case .fail:
                            //    ⟨Fail, i0, (p, i1, c1) : e, c0⟩    any                 ⇒ ⟨p, i1, e, c1⟩
                            p = alt; i = i1; tree.discard(t1)
                            break rep
                        case let .commit(commit):
                            //                   ⟨p, i, h : e, c⟩    Commit l            ⇒ ⟨p + l, i, e, c⟩
                            p = commit
                            break rep
                        case let .rep(rep):
                            //     ⟨p0, i0, (p1, i1, c1) : e, c0⟩    PartialCommit l     ⇒ ⟨p0 + l, i0, (p1, i0, c0) : e, c0⟩
                            p = rep
                        case let .back(next):
                            //     ⟨p0, i0, (p1, i1, c1) : e, c0⟩    BackCommit l        ⇒ ⟨p0 + l, i1, e, c1⟩
                            p = next; i = i1; tree.discard(t1)
                            break rep
                        case .fail2:
                            //                   ⟨p, i, h : e, c⟩    FailTwice           ⇒ ⟨Fail, i, e, c⟩
                            return .fail
                        default:
                            assertionFailure(".alt unexpected seq result \(r)")
                            return .fail
                        }
                    }
                case .commit(_), .rep(_), .back(_), .fail, .fail2, ._dummy:
                    return program[p]
                }
            }
        }
    }
    
    // == Failure reporting ==

    #if DEBUG
    internal func failReport(_ t: UniText, _ fail: Fail) {
        // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextLayout/Tasks/CountLines.html
        var lines = 0, lineStart = 0
        while true {
            let next = lineStart + t.lineRange(for: NSRange(location: lineStart, length: 0)).length
            if next > fail.i { break }
            lines += 1; lineStart = next
        }
        print("parse FAIL",
              //"at", fail.i,
              //"lastLineStart", lastLineStart ?? "nil",
              "line", lines,
              "char", fail.i - lineStart + 1,
              PEMachineCoreN.failText(t, fail.i) )
        fail.stack.reversed().forEach { cs in
            if case let .call(call) = program[cs.ret-1] {
                if !ignore[call] {
                    print("   ", symbols[call], PEMachineCoreN.failText(t, cs.index))
                    #if false
                    for p in start[symRaw]..<program.endIndex {
                        print("       ", p, program[p])
                        if case .ret = program[p] { break }
                    }
                    #endif
                }
            } else {
                assertionFailure(".ret expected .call \(program[cs.ret-1])")
            }
        }
    }

    internal static func failText(_ t: UniText, _ i: UniTextIndex) -> String {
        uniString(t, i..<t.length).prefix(40).debugDescription
    }
    #endif

    public init(core:PEMachineCore) {
        self.program = core.program.map { inst->Inst in
            return switch inst {
            case .any(let n):
                    .any(n)
            case .any1:
                    .any1
            case .chr(let c):
                    .chr(c)
            case .lit(let first, let rest):
                    .lit(first, PEMachineCoreN.uniText(PEMachineCore.uniString(rest)))
            case .chrs(let cs):
                    .chrs(PEMachineCoreN.uniText(PEMachineCore.uniString(cs)))
            case .chrset(let cs):
                    .chrset(cs)
            case .chrset1(let cs):
                    .chrset1(cs)
            case .span(let ss):
                    .span(PEMachineCoreN.uniText(PEMachineCore.uniString(ss)))
            case .spanset(let ss):
                    .spanset(ss)
            case .spanset1(let ss):
                    .spanset1(ss)
            case .range(let lower, let upper):
                    .range(lower, upper)
            case .call(let s):
                    .call(s)
            case .alt(let a):
                    .alt(a)
            case .commit(let c):
                    .commit(c)
            case .rep(let r):
                    .rep(r)
            case .back(let b):
                    .back(b)
            case .fail:
                    .fail
            case .fail2:
                    .fail2
            case .ret:
                    .ret
            case ._dummy:
                    ._dummy
            }
        }
        self.symbols = core.symbols
        self.ignore = core.ignore
        self.start = core.start
    }
}

public struct PEMachineN<Symbol:Sendable> {
    public typealias Symbols = [Symbol]
    let machine: PEMachine<Symbol>
    let core: PEMachineCoreN
    
    public init(machine:PEMachine<Symbol>) {
        self.machine = machine
        self.core = PEMachineCoreN(core: machine.core)
    }

    private func makeResult(_ mr: PEMachineCoreN.CoreResult, _ text: PEMachineCoreN.UniText)->PEMachine<Symbol>.ParseResult {
        // build full ParseResult from internal CoreResult
        switch mr {
          
        case .success(index: let index, tree: let tree):
            return .success(PEMachine<Symbol>.ParseResult.Success(text: PEMachineCore.UniText(String(text).utf16),
                                                                  endIndex: index,
                                                                  tree: tree,
                                                                  symbols: machine.symbols ))

        #if DEBUG
        case .failure(let fail):
            return .failure(PEMachine<Symbol>.ParseResult.Failure(text: PEMachineCore.UniText(String(text).utf16),
                                                                  endIndex: fail.i,
                                                                  stack: failStack(fail),
                                                                  symbols: machine.symbols ))

        #else
        case .failure:
            return .failure(PEMachine<Symbol>.ParseResult.Failure())
        #endif
        }
    }
    
    #if DEBUG
    private func failStack(_ fail: PEMachineCoreN.Fail) -> [(Symbols.Index, PEMachineCoreN.UniTextIndex)] {
        fail.stack.compactMap { cs->(Symbols.Index, PEMachineCoreN.UniTextIndex)? in
            if case let .call(call) = core.program[cs.ret-1] {
                return core.ignore[call] ? nil : (call, cs.index)
            } else {
                assertionFailure(".ret expected .call \(core.program[cs.ret-1])")
                return nil
            }
        }
    }
    #endif

    func parse(_ symbol: PEMachineCoreN.Symbols.Index, _ text: String)->PEMachine<Symbol>.ParseResult {
        let uctext = PEMachineCoreN.uniText(text)
        let mr = core.parse(symbol, uctext)
        return makeResult(mr, uctext)
    }

    public func symbolIndex(_ symName: String)->PEMachineCoreN.Symbols.Index? {
        return core.symbols.firstIndex(of: symName)
    }
    
    public func parse(_ symName: String, _ text: String)->PEMachine<Symbol>.ParseResult {
        let sym = symbolIndex(symName)!
        return parse(sym, text)
    }
}
