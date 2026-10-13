//
//  PEMachine.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-20.
//

public struct PEMachine<Symbol:Sendable>: Sendable {
    
    // The core is defined separately in hope the compiler will better optimize
    // the core 'parse' function. Generics are applied in this wrapper.
    
    public typealias Symbols = [Symbol]
    public let symbols: Symbols
    let core: PEMachineCore
    public typealias UniView = PEMachineCore.UniView
    public typealias UniChar = PEMachineCore.UniChar
    public typealias Tree = PEMachineCore.Tree
    
    public enum ParseResult {
        public struct Success {
            public let text: UniView,
                       endIndex: UniView.Index,
                       tree: Tree,
                       symbols: Symbols
            public func nodeText(_ index: Tree.Index)->UniView.SubSequence {
                text[tree[index].value]
            }
            public func nodeString(_ index: Tree.Index)->String {
                String(nodeText(index))!
            }
            public func nodeSymbol(_ index: Tree.Index)->Symbol {
                symbols[tree[index].identifier]
            }
            public func nodeId(_ index: Tree.Index)->Int {
                tree[index].identifier
            }
        }
        public struct Failure {
            #if DEBUG
            public let text: UniView,
                       endIndex: UniView.Index,
                       stack: [(PEMachineCore.Symbols.Index, UniView.Index)],
                       symbols: Symbols
            #endif
        }
        case success(Success)
        case failure(Failure)
    }

    public func parse(_ symbol: Symbol, _ text: String, trace: Bool = false)->ParseResult
                        where Symbol: RawRepresentable,
                              Symbol.RawValue == Int {
        let uctext = PEMachineCore.uc(text)
        let mr = core.parse(symbol.rawValue, uctext, trace: trace)
        return makeResult(mr, uctext)
    }

    public func parse(_ symbol: Symbol, _ uctext: UniView, trace: Bool = false)->ParseResult
                        where Symbol: RawRepresentable,
                              Symbol.RawValue == Int {
        let mr = core.parse(symbol.rawValue, uctext, trace: trace)
        return makeResult(mr, uctext)
    }
    
    private func makeResult(_ mr: PEMachineCore.CoreResult, _ text: UniView)->ParseResult {
        // build full ParseResult from internal CoreResult
        switch mr {
          
        case .success(index: let index, tree: let tree):
            return .success(ParseResult.Success(text: text,
                                                endIndex: index,
                                                tree: tree,
                                                symbols: symbols ))

        #if DEBUG
        case .failure(let fail):
            return .failure(ParseResult.Failure(text: text,
                                                endIndex: fail.i,
                                                stack: failStack(fail),
                                                symbols: symbols ))

        #else
        case .failure:
            return .failure(ParseResult.Failure())
        #endif
        }
        
    }
    
    #if DEBUG
    private func failStack(_ fail: PEMachineCore.Fail) -> [(PEMachineCore.Symbols.Index, String.Index)] {
        fail.stack.compactMap { cs in
            if case let .call(call) = core.program[cs.ret-1] {
                return core.ignore[call] ? nil : (call, cs.index)
            } else {
                assertionFailure(".ret expected .call \(core.program[cs.ret-1])")
                return nil
            }
        }
    }
    #endif

    func parse(_ symbol: PEMachineCore.Symbols.Index, _ text: String, trace: Bool = false)->ParseResult {
        let uctext = PEMachineCore.uc(text)
        let mr = core.parse(symbol, uctext, trace: trace)
        return makeResult(mr, uctext)
    }

    public func symbolIndex(_ symName: String)->PEMachineCore.Symbols.Index? {
        return core.symbols.firstIndex(of: symName)
    }
    
    public func parse(_ symName: String, _ text: String, trace: Bool = false)->ParseResult {
        let sym = symbolIndex(symName)!
        return parse(sym, text, trace: trace)
    }
    
    func parse(_ symbol: PEMachineCore.Symbols.Index, _ uctext: UniView, trace: Bool = false)->ParseResult {
        let mr = core.parse(symbol, uctext, trace: trace)
        return makeResult(mr, uctext)
    }

    public func parse(_ symName: String, _ uctext: UniView, trace: Bool = false)->ParseResult {
        let sym = symbolIndex(symName)!
        return parse(sym, uctext, trace: trace)
    }

}

#if DEBUG
extension PEMachine.ParseResult.Failure {
    public func printFailure() {
        let lineEnds = text[..<endIndex].indices(of: PEMachineCore.uc("\n")).ranges,
            lastLineStart = lineEnds.last?.upperBound
        //print(lineEnds)
        print("parse FAIL",
              //"at", fail.i,
              //"lastLineStart", lastLineStart ?? "nil",
              "line", lineEnds.reduce(1, { partialResult, range in
            partialResult+String(text[range])!.count
        }),
              "char", (String(text[(lastLineStart ?? text.startIndex)..<endIndex])?.count ?? 0)+1,
              PEMachineCore.failText(text, endIndex) )
        stack.reversed().forEach { (cs: (PEMachineCore.Symbols.Index, PEMachine.UniView.Index)) in
            print("   ", symbols[cs.0], PEMachineCore.failText(text, cs.1))
        }
    }

}
#endif

import class Foundation.NSString // String(format:,...)

extension PEMachine.ParseResult.Success {
    func printTree(_ index: PEMachine.Tree.Index, depth: Int=0) {
        let indent = String(repeating: "  ", count: depth)
        let n = tree.nodes[index]
        let t = nodeString(index)
        print(String(format: "%6ld %6ld %5ld %5ld %5ld %@ %@",
                     text.distance(from: text.startIndex, to: n.value.lowerBound),
                     t.count,
                     index, n.first, n.next,
                     indent+String(describing: symbols[n.identifier]),
                     ((t.count < 40) ? t : t.prefix(40)+"...").debugDescription ))
        tree.childIndices(index)?.forEach { printTree($0, depth: depth+1) }
    }
    public func printTree() {
        print("Offset Length  Node First  Next Symbol \"Text\"")
        printTree(tree.root)
    }
}

