//
//  PEMachine.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-20.
//

extension PEMachine {

    // The PEMahine itself is immutable. A separate Builder struct is used to
    // construct the program from a grammar.
    
    typealias Program = PEMachineCore.Program
    typealias Inst = PEMachineCore.Inst

    struct Builder {
        var symbols: Symbols,
            program: Program,
            start: [Program.Index],
            ignore: [Bool],
            errors: [String]
        
        // == Compiling helpers ==
        
        internal mutating func dummy()->Program.Index {
            let d = program.count
            program.append(._dummy)
            return d
        }
        
        internal mutating func place(_ p: Program.Index, _ i: Inst) {
            if case ._dummy = program[p] {
                program[p] = i
            } else {
                assertionFailure("place expecting ._dummy, found \(program[p])")
                program[p] = i
            }
        }

    }

}
