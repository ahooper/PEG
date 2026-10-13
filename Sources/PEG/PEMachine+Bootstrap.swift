//
//  PEGBootstrap.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-20.
//

extension PEMachine.Builder {
    
    enum PE: CustomStringConvertible, Sendable
                where Symbol: RawRepresentable,
                      Symbol.RawValue == Int,
                      Symbol: Sendable {
        case any(Int)
        case lit(String)
        case chrs(String)
        case range(Character,Character)
        case call(Symbol)
        indirect case seq([PE])
        indirect case alt([PE])
        indirect case rep(PE)
        indirect case rep1(PE)
        indirect case opt(PE)
        indirect case not(PE)
        indirect case pred(PE)
        var description: String {
            switch self {
            case let .any(any):
                "any(\(any))"
            case let .lit(lit):
                "lit(\(lit.debugDescription)"
            case let .chrs(chrs):
                "chrs(\(chrs.debugDescription))"
            case let .range(lower,upper):
                "range(\(lower.debugDescription),\(upper.debugDescription))"
            case let .call(call):
                "call(\(call))"
            case let .seq(seq):
                "seq([\(seq.map({ $0.description }).joined(separator: ", "))])"
            case let .alt(alt):
                "alt([\(alt.map({ $0.description }).joined(separator: ", "))])"
            case let .rep(rep):
                "rep(\(rep.description))"
            case let .rep1(rep1):
                "rep1(\(rep1.description))"
            case let .opt(opt):
                "opt(\(opt.description))"
            case let .not(not):
                "not(\(not.description))"
            case let .pred(pred):
                "pred(\(pred.description))"
            }
        }
    }
    
    typealias Bootstrap = [Symbol: PE]
                    where Symbol: Hashable & RawRepresentable & CaseIterable,
                    Symbol.RawValue == Int

    init(grammar: Bootstrap)
                        where Symbol: RawRepresentable & CaseIterable,
                              Symbol.RawValue == Int,
                              Symbol: Sendable {
        symbols = [Symbol](Symbol.allCases) // https://stackoverflow.com/a/50177561
        program = []
        start = [PEMachine.Program.Index](repeating: -1,
                                          count: symbols.count)
        ignore = [Bool](repeating: false,
                         count: symbols.count)
        errors = []
        for s in grammar.keys {
            start[s.rawValue] = program.count
            ignore[Int(s.rawValue)] = String(describing: s).first == "_"
            compile(grammar[s]!)
            program.append(.ret)
        }
        let undef = program.compactMap {
            if case let .call(call) = $0,
               start[Int(call)] < 0 {
                call
            } else {
                nil
            }
        }
        if !undef.isEmpty { errors.append("Undefined symbols \(undef)") }
    }
    
    private mutating func compile(_ def: PE)
                    where Symbol: Hashable & RawRepresentable & CaseIterable,
                    Symbol.RawValue == Int {
        // This compile does not do the optimizations of the main
        // line one (in PEMachine+chpeg.swift), but it is only
        // used on grammar definitions which are usually small.
        switch def {
        case .any(let n):
            program.append((n == 1) ? .any1 : .any(n))
        case .lit(let lit):
            if lit.count == 1 {
                program.append(.chr(PEMachineCore.uc(lit).first!))
            } else {
                program.append(.lit(PEMachineCore.uc(lit.first!), PEMachineCore.uc(String(lit.dropFirst()))))
            }
        case .chrs(let chrs):
            //program.append(.chrs(Self.uc(chrs)))
            program.append(.chrset(chrsBitSet(chrs)))
        case .range(let lower, let upper):
            program.append(.range(PEMachineCore.uc(lower), PEMachineCore.uc(upper)))
        case .call(let call):
            program.append(.call(call.rawValue))
        case .seq(let seq):
            // E F G:
            //      E
            //      F
            //      G
            for s in seq { compile(s) }
        case .alt(let alt):
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
            alt.dropLast().forEach {
                let a = dummy()
                compile($0)
                joins.append(dummy())
                place(a, .alt(program.endIndex))
            }
            compile(alt.last!)
            joins.forEach { place($0, .commit(program.endIndex)) }
        case .rep(let rep):
            if case .chrs(let chrs) = rep {
                program.append(.spanset(chrsBitSet(chrs)))
                break
            }
            // E*:
            //      alt a
            //  r:  E
            //      rep r
            //  a:
            let a = dummy()
            let r = program.endIndex
            compile(rep)
            program.append(.rep(r))
            place(a, .alt(program.endIndex))
        case .rep1(let rep):
            if case .chrs(let chrs) = rep {
                program.append(.chrset(chrsBitSet(chrs)))
                program.append(.spanset(chrsBitSet(chrs)))
                break
            }
            // E+:
            //      E
            //      alt a
            //  r:  E
            //      rep r
            //  a:
            compile(rep)
            let a = dummy()
            let r = program.endIndex
            compile(rep)
            program.append(.rep(r))
            place(a, .alt(program.endIndex))
        case .opt(let opt):
            // E?:
            //      alt a
            //      E
            //      commit a
            //  a:
            let a = dummy()
            compile(opt)
            let join = dummy()
            place(join, .commit(program.endIndex))
            place(a, .alt(program.endIndex))
        case .not(let not):
            // !E:
            //      alt a
            //      E
            //      fail2
            //  a:
            let p = dummy()
            compile(not)
            program.append(.fail2)
            place(p, .alt(program.endIndex))
        case .pred(let pred):
            // &E:
            //      alt f
            //      E
            //      back s
            //  f:  fail
            //  s:
            let a = dummy()
            compile(pred)
            let b = dummy()
            place(a, .alt(program.endIndex))
            program.append(.fail)
            place(b, .back(program.endIndex))
        }
    }
    
    private func chrsBitSet(_ chrs: String) -> BitSet {
        return BitSet(PEMachineCore.uc(chrs).map({UInt32($0)}))
    }

}

extension PEMachine {
    init(grammar: Builder.Bootstrap)
                        where Symbol: RawRepresentable & CaseIterable,
                              Symbol.RawValue == Int,
                              Symbol: Sendable {
        symbols = [Symbol](Symbol.allCases)
        let build = Builder(grammar: grammar)
        precondition(build.errors.isEmpty)
        core = PEMachineCore(symbols: build.symbols.map ({ String(describing: $0) }),
                             program: build.program,
                             start: build.start,
                             ignore: build.ignore)
    }
}
