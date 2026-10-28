//
//  PEMachine+export.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-26.
//

import struct Foundation.Date

extension PEMachine {
        
    public func exportProgram(name: String, source: String? = nil) {
        print("""
            // generated \(Date().formatted(Date.ISO8601FormatStyle()))
            """)
        if let source {
            print("""
                /*
                \(source)
                */
                """)
        }
        print("""
            enum \(name)MachineSymbol: Int, CaseIterable, Sendable {
                case
            """)
        print("       ", symbols.map({ String(describing: $0) }).joined(separator: ",\n        "))
        print("""
            }
            let \(name)Machine = PEMachine<\(name)MachineSymbol>(
            """)
//        symbols.indices.forEach {
//            print("        /*\($0)*/ .\(symbols[$0]),")
//        }
        print("""
                program: [
            """)
        let symbolsByStart = symbols.indices.sorted { a, b in
            core.start[a] < core.start[b]
        }
        var symInd = symbolsByStart.startIndex
        core.program.indices.forEach {
            if symInd < symbolsByStart.endIndex,
               $0 == core.start[symbolsByStart[symInd]] {
                print("    // \(symbols[symbolsByStart[symInd]]):")
                symInd += 1
            }
            let inst = core.program[$0]
            switch inst {
            case let .lit(first,rest):
                print("       /*\($0)*/.lit(\(first), PEMachineCore.uniText(\(PEMachineCore.uniString(rest).debugDescription))),")
            case let .chrs(uc):
                print("       /*\($0)*/.chrs(PEMachineCore.uniText(\(PEMachineCore.uniString(uc).debugDescription))),")
            case let .span(uc):
                print("       /*\($0)*/.span(PEMachineCore.uniText(\(PEMachineCore.uniString(uc).debugDescription))),")
            case let .call(call):
                print("       /*\($0)*/.\(inst), // \(symbols[call])")
            default:
                print("       /*\($0)*/.\(inst),")
            }
        }
        print("""
                    ],
                start: [
            """)
        symbols.indices.forEach {
            print("        /*\(symbols[$0])*/ \(core.start[$0]),")
        }
        print("""
                    ],
                ignore: [
            """)
        symbols.indices.forEach {
            print("        /*\(symbols[$0])*/ \(core.ignore[$0]),")
        }
        print("""
                    ]
             """)        
        print("""
            )
            """)
    }
    
    init(program: Program, start: [Program.Index], ignore: [Bool]) where Symbol: CaseIterable {
        self.symbols = Symbols(Symbol.allCases)
        self.core = PEMachineCore(symbols: self.symbols.map{String(describing: $0)},
                                  program: program,
                                  start: start,
                                  ignore: ignore)
    }

}
