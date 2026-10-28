//
//  PEMachineCore.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-20.
//

/*  The parsing machine is closely based on the Lua lpeg machine described
 *  by Ierusalimschy: https://www.inf.puc-rio.br/~roberto/docs/peg.pdf
 *  The state transitions are from Figures 2 and 3.
 */

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
public struct PEMachineCore {
    
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

    public typealias UniText = Array<Unicode.UTF16.CodeUnit>
        // Array seems to have a slight performance advantage over ContiguousArray
    internal typealias UniChar = UniText.Element
    internal static func uniText(_ s: String)->UniText { UniText(s.utf16) }
    internal static func uniChar(_ c: Character)->UniChar { c.utf16.first! }
    internal static func uniString(_ t: UniText)->String { String(validating: t, as: Unicode.UTF16.self)! }
    internal static func uniString(_ ts: UniText.SubSequence)->String { String(validating: ts, as: Unicode.UTF16.self)! }
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
    public typealias Tree = LinearTree<Symbols.Index, Range<UniText.Index>>
    
    #if DEBUG
    struct CallStack {
        let ret: Program.Index,
            index: UniText.Index,
            tree: Tree.Index
    }
    struct Fail {
        let i: UniText.Index,
            stack: ArraySlice<CallStack>
    }
    #endif
    
    // Non-generic result in hope of better optimization
    internal enum CoreResult {
        case success(index: UniText.Index, tree: Tree)
        #if DEBUG
        case failure(Fail)
        #else
        case failure
        #endif
    }

    func parse(_ sym: Symbols.Index, _ t: UniText, trace: Bool = false)->CoreResult {
        var i = t.startIndex,
            tree = Tree()
        #if DEBUG
        var furthestFail: Fail?
        var callStack: [CallStack] = [] // Simulated call stack
        callStack.reserveCapacity(100)
        #endif
        if case .ret = seq(start[sym], 0) {
            if !ignore[sym] {
                if trace { print(t.startIndex, i, sym) }
                tree.end(sym, tree.nodes.startIndex, t.startIndex..<i)
            }
            return .success(index: i, tree: tree)
        } else {
            #if DEBUG
            if let furthestFail {
                //failReport(t, furthestFail)
                return .failure(furthestFail)
            } else {
                return .failure(Fail(i: t.startIndex, stack: []))
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
                    if i < t.endIndex,
                       let j = t.index(i, offsetBy: n, limitedBy: t.endIndex) {
                        i = j
                        p += 1
                    } else {
                        return .fail
                    }
                case  .any1:
                    //    ⟨p, i, e, c⟩    Any n, i + n ≤ |S|  ⇒ ⟨p + 1, i + n, e, c⟩
                    //    ⟨p, i, e, c⟩    Any n, i + n > |S|  ⇒ ⟨Fail, i, e, c⟩
                    if i < t.endIndex {
                        i = t.index(after: i)
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chr(chr):
                    //    ⟨p, i, e, c⟩    Char x, S[i] = x    ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Char x, S[i] ≠ x    ⇒ ⟨Fail, i, e, c⟩
                    if i < t.endIndex,
                       t[i] == chr {
                        i = t.index(after: i)
                        p += 1
                    } else {
                        return .fail
                    }
                case let .lit(first,rest):
                    //    ⟨p, i, e, c⟩    Char x, S[i] = x    ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Char x, S[i] ≠ x    ⇒ ⟨Fail, i, e, c⟩
                    if i < t.endIndex,
                       t[i] == first,
                       t.suffix(from: t.index(after: i)).starts(with: rest) {
                        i = t.index(i, offsetBy: rest.count+1)
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chrs(chrs):
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∈ X ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∉ X ⇒ ⟨Fail, i, e, c⟩
                    if i < t.endIndex,
                       chrs.contains(t[i]) {
                        i = t.index(after: i)
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chrset(chrset):
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∈ X ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∉ X ⇒ ⟨Fail, i, e, c⟩
                    if i < t.endIndex,
                       chrset.contains(UInt32(t[i])) {
                        i = t.index(after: i)
                        p += 1
                    } else {
                        return .fail
                    }
                case let .chrset1(word):
                    if i < t.endIndex,
                       BitSet.wordContains(word, UInt32(t[i])) {
                        i = t.index(after: i)
                        p += 1
                    } else {
                        return .fail
                    }
                case let .spanset(spanset):
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∈ X    ⇒ ⟨p, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∉ X    ⇒ ⟨p + 1, i, e, c⟩
                    while i < t.endIndex,
                          spanset.contains(UInt32(t[i])) {
                        i = t.index(after: i)
                    }
                    p += 1
                case let .spanset1(word):
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∈ X    ⇒ ⟨p, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∉ X    ⇒ ⟨p + 1, i, e, c⟩
                    while i < t.endIndex,
                          BitSet.wordContains(word, UInt32(t[i])) {
                        i = t.index(after: i)
                    }
                    p += 1
                case let .span(span):
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∈ X    ⇒ ⟨p, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Span X, S[i] ∉ X    ⇒ ⟨p + 1, i, e, c⟩
                    while i < t.endIndex,
                          span.contains(t[i]) {
                        i = t.index(after: i)
                    }
                    p += 1
                case let .range(lower, upper):
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∈ X ⇒ ⟨p + 1, i + 1, e, c⟩
                    //    ⟨p, i, e, c⟩    Charset X, S[i] ∉ X ⇒ ⟨Fail, i, e, c⟩
                    if i < t.endIndex,
                       lower <= t[i],
                       t[i] <= upper {
                        i = t.index(after: i)
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
        let lineEnds = t[..<fail.i].indices(of: Self.uniChar("\n")).ranges,
            lastLineStart = lineEnds.last?.upperBound
        //print(lineEnds)
        print("parse FAIL",
              //"at", fail.i,
              //"lastLineStart", lastLineStart ?? "nil",
              "line", lineEnds.reduce(1, { partialResult, range in
            partialResult+PEMachineCore.uniString(t[range]).count
        }),
              "char", PEMachineCore.uniString(t[(lastLineStart ?? t.startIndex)..<fail.i]).count+1,
              PEMachineCore.failText(t, fail.i) )
        fail.stack.reversed().forEach { cs in
            if case let .call(call) = program[cs.ret-1] {
                if !ignore[call] {
                    print("   ", symbols[call], PEMachineCore.failText(t, cs.index))
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

    internal static func failText(_ t: UniText, _ i: UniText.Index) -> String {
        uniString(t[i..<t.endIndex]).prefix(40).debugDescription
    }
    #endif

    
}
