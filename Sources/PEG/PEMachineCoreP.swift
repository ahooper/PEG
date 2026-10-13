//
//  PEMachineCoreP.swift
//  pgen
//
//  Created by Andy Hooper on 2026-10-08.
//
//  https://www.swift.org/blog/migrating-truetype-hinting-to-swift/
//  https://github.com/apple/truetype-hinting-interpreter-example.git
//  https://github.com/swiftwasm/WasmKit.git

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

public struct PEMachineCoreP  {
    
    // The PEMachine itself is immutable. A separate Builder struct is used to
    // construct the program from a grammar.
    
    // The core is defined separately in hope the compiler will better optimize
    // the core 'parse' function.
    
    public typealias Symbols = [String]
    public let symbols: Symbols
    
    // == Text representation ==
    
    //  UTF16 is used for text elements to reduce the size of program instructions
    //  containing them, to avoid varying length elements, and to match the
    //  representation in NSAttributedString for  editors.
    
    public typealias UniView = String.UTF16View
    static func uc(_ s: String)->UniView { s.utf16 }
    public typealias UniChar = UniView.Element
    static func uc(_ c: Character)->UniChar { c.utf16.first! }
    
    // == Program instructions ==
    
    typealias Program = [Inst]
    typealias Program_Pointer = UnsafePointer<Program.Element>
    enum Inst: DebugEquatable {
        case any(Int)
        case any1
        case chr(UniChar)
        case lit(UniChar,UniView)
        case chrs(UniView)
        case chrset(BitSet)
        case chrset1(BitSet.Word)
        case span(UniView)
        case spanset(BitSet)
        case spanset1(BitSet.Word)
        case range(UniChar,UniChar) //TODO?: multiple ranges?
        case call(Symbols.Index)
        case alt(Program_Pointer)
        case commit(Program_Pointer)
        case rep(Program_Pointer)
        case back(Program_Pointer)
        case fail
        case fail2
        case ret
        case _dummy
    }
    let program: Program,
        start: [Program_Pointer],
        ignore: [Bool]
        
    public func printProgram() {
        for si in symbols.indices {
            print("\(symbols[si])(\(si)):")
            for p in start[si]... {
                print("  ", p, p.pointee)
                if case .ret = p.pointee { break }
            }
        }
    }

    // == Parsing ==
    
    // Many parse tree nodes are discarded in backtracking, so minimize
    // their construction cost.
    public typealias Tree = LinearTree<Symbols.Index, Range<UniView.Index>>
    
    #if DEBUG
    struct CallStack {
        let ret: Program_Pointer,
            index: UniView.Index,
            tree: Tree.Index
    }
    struct Fail {
        let i: UniView.Index,
            stack: ArraySlice<CallStack>
    }
    #endif
    
    // Non-generic result in hope of better optimization
    internal enum CoreResult {
        case success(index: UniView.Index, tree: Tree)
        #if DEBUG
        case failure(Fail)
        #else
        case failure
        #endif
    }

    func parse(_ sym: Symbols.Index, _ t: UniView)->CoreResult {
        var i = t.startIndex,
            tree = Tree()
        #if DEBUG
        var furthestFail: Fail?
        var callStack: [CallStack] = [] // Simulated call stack
        callStack.reserveCapacity(100)
        #endif
        if case .ret = seq(start[sym], 0) {
            if !ignore[sym] {
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

        func seq(_ s: Program_Pointer, _ nest: Int)->Inst {
            // caller is responsible to restore i and tree on failure(->.fail)
            var p = s
            while true {
                switch p.pointee {
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
                            tree.end(call, t0, i0..<i)
                        }
                        p += 1
                    case .fail:
                        //               ⟨Fail, i, p : e, c⟩    any                 ⇒ ⟨Fail, i, e, c⟩
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
                    return p.pointee
                }
            }
        }
    }
    
    // == Failure reporting ==

    #if DEBUG
    internal func failReport(_ t: UniView, _ fail: Fail) {
        let lineEnds = t[..<fail.i].indices(of: Self.uc("\n")).ranges,
            lastLineStart = lineEnds.last?.upperBound
        //print(lineEnds)
        print("parse FAIL",
              //"at", fail.i,
              //"lastLineStart", lastLineStart ?? "nil",
              "line", lineEnds.reduce(1, { partialResult, range in
            partialResult+String(t[range])!.count
        }),
              "char", (String(t[(lastLineStart ?? t.startIndex)..<fail.i])?.count ?? 0)+1,
              PEMachineCoreP.failText(t, fail.i) )
        fail.stack.reversed().forEach { cs in
            if case let .call(call) = cs.ret.advanced(by: -1).pointee {
                if !ignore[call] {
                    print("   ", symbols[call], PEMachineCoreP.failText(t, cs.index))
                    #if false
                    for p in start[symRaw]..<program.endIndex {
                        print("       ", p, p.pointee)
                        if case .ret = p.pointee { break }
                    }
                    #endif
                }
            } else {
                assertionFailure(".ret expected .call \(cs.ret.advanced(by: -1).pointee)")
                print(".ret expected .call \(cs.ret.advanced(by: -1).pointee)")
            }
        }
    }

    internal static func failText(_ t: UniView, _ i: UniView.Index) -> String {
        (String(t[i...])?.prefix(40) ?? "").debugDescription
    }
    #endif

    
    init(core: PEMachineCore) {
        symbols = core.symbols
        ignore = core.ignore
        var prog = Program(repeating: ._dummy, count: core.program.count)
        for p in core.program.indices {
            switch core.program[p] {
            case let .any(n):
                prog[p] = .any(n)
            case .any1:
                prog[p] = .any1
            case let .chr(chr):
                prog[p] = .chr(chr)
            case let .lit(first,rest):
                prog[p] = .lit(first,rest)
            case let .chrs(chrs):
                prog[p] = .chrs(chrs)
            case let .chrset(chrset):
                prog[p] = .chrset(chrset)
            case let .chrset1(word):
                prog[p] = .chrset1(word)
            case let .spanset(spanset):
                prog[p] = .spanset(spanset)
            case let .spanset1(word):
                prog[p] = .spanset1(word)
            case let .span(span):
                prog[p] = .span(span)
            case let .range(lower, upper):
                prog[p] = .range(lower, upper)
            case let .call(call):
                prog[p] = .call(call)
            case .ret:
                prog[p] = .ret
            case let .alt(alt):
                prog[p] = .alt(pp(prog, alt))
            case .fail:
                prog[p] = .fail
            case let .commit(commit):
                prog[p] = .commit(pp(prog, commit))
            case let .rep(rep):
                prog[p] = .rep(pp(prog, rep))
            case let .back(next):
                prog[p] = .back(pp(prog, next))
            case .fail2:
                prog[p] = .fail2
            case ._dummy:
                assertionFailure("_dummy should have been replaced")
                prog[p] = ._dummy
            }
        }
        program = prog
        var st = [Program_Pointer](repeating: pp(prog, 0), count: core.start.count)
        for s in core.start.indices {
            st[s] = pp(prog, core.start[s])
        }
        start = st
        func pp(_ p:Program_Pointer, _ a:Int)->Program_Pointer { p+a }
    }
    
}

public struct PEMachineP<Symbol:Sendable> {
    public typealias Symbols = [Symbol]
    private let machine: PEMachine<Symbol>
    let core: PEMachineCoreP

    public init(machine:PEMachine<Symbol>) {
        self.machine = machine
        self.core = PEMachineCoreP(core: machine.core)
    }

    private func makeResult(_ mr: PEMachineCoreP.CoreResult, _ text: PEMachineCoreP.UniView)->PEMachine<Symbol>.ParseResult {
        // build full ParseResult from internal CoreResult
        switch mr {
          
        case .success(index: let index, tree: let tree):
            return .success(PEMachine<Symbol>.ParseResult.Success(text: text,
                                                                  endIndex: index,
                                                                  tree: tree,
                                                                  symbols: machine.symbols ))

        #if DEBUG
        case .failure(let fail):
            return .failure(PEMachine<Symbol>.ParseResult.Failure(text: text,
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
    private func failStack(_ fail: PEMachineCoreP.Fail) -> [(PEMachineCore.Symbols.Index, String.Index)] {
        fail.stack.compactMap { cs->(PEMachineCore.Symbols.Index, String.Index)? in
            if case let .call(call) = (cs.ret-1).pointee {
                return core.ignore[call] ? nil : (call, cs.index)
            } else {
                assertionFailure(".ret expected .call \((cs.ret-1).pointee)")
                return nil
            }
        }
    }
    #endif

    func parse(_ symbol: PEMachineCoreP.Symbols.Index, _ text: String)->PEMachine<Symbol>.ParseResult {
        let uctext = PEMachineCoreP.uc(text)
        let mr = core.parse(symbol, uctext)
        return makeResult(mr, uctext)
    }

    public func symbolIndex(_ symName: String)->PEMachineCoreP.Symbols.Index? {
        return core.symbols.firstIndex(of: symName)
    }
    
    public func parse(_ symName: String, _ text: String)->PEMachine<Symbol>.ParseResult {
        let sym = symbolIndex(symName)!
        return parse(sym, text)
    }
}
