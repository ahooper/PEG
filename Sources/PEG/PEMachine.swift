//
//  PEMachine.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-20.
//

public struct PEMachine<Symbol> {
    
    // The core is defined separately in hope the compiler will better optimize
    // the core 'parse' function. Generics are applied in this wrapper.
    
    public typealias Symbols = [Symbol]
    public let symbols: Symbols
    let core: PEMachineCore
    public typealias UniText = PEMachineCore.UniText
    public typealias Tree = PEMachineCore.Tree
    
    public enum ParseResult {
        public class Success {
            // a class because this is created infrequently, but copied
            // frequently in Contexts.
            public let text: UniText,
                       endIndex: UniText.Index,
                       tree: Tree,
                       symbols: Symbols
            init(text: UniText, endIndex: UniText.Index, tree: Tree, symbols: Symbols) {
                self.text = text
                self.endIndex = endIndex
                self.tree = tree
                self.symbols = symbols
            }
            public func nodeText(_ index: Tree.Index)->UniText.SubSequence {
                text[tree[index].value]
            }
            public func nodeString(_ index: Tree.Index)->String {
                PEMachineCore.uniString(nodeText(index))
            }
            public func nodeSymbol(_ index: Tree.Index)->Symbol {
                symbols[tree[index].identifier]
            }
            public func nodeId(_ index: Tree.Index)->Int {
                tree[index].identifier
            }
            public func nodeRange(_ index: Tree.Index, _ source: String)->Range<String.Index> {
                String.Index(utf16Offset: tree[index].value.lowerBound, in: source) ..<
                    String.Index(utf16Offset: tree[index].value.upperBound, in: source)
            }
        }
        public class Failure {
            #if DEBUG
            public let text: UniText,
                       endIndex: UniText.Index,
                       stack: [(PEMachineCore.Symbols.Index, UniText.Index)],
                       symbols: Symbols
            init(text: UniText, endIndex: UniText.Index, stack: [(PEMachineCore.Symbols.Index, UniText.Index)], symbols: Symbols) {
                self.text = text
                self.endIndex = endIndex
                self.stack = stack
                self.symbols = symbols
            }
            #endif
        }
        case success(Success)
        case failure(Failure)
    }

    public func parse(_ symbol: Symbol, _ text: String, trace: Bool = false)->ParseResult
                        where Symbol: RawRepresentable,
                              Symbol.RawValue == Int {
        let uctext = PEMachineCore.uniText(text)
        let mr = core.parse(symbol.rawValue, uctext, trace: trace)
        return makeResult(mr, uctext)
    }

    public func parse(_ symbol: Symbol, _ uctext: UniText, trace: Bool = false)->ParseResult
                        where Symbol: RawRepresentable,
                              Symbol.RawValue == Int {
        let mr = core.parse(symbol.rawValue, uctext, trace: trace)
        return makeResult(mr, uctext)
    }
    
    private func makeResult(_ mr: PEMachineCore.CoreResult, _ text: UniText)->ParseResult {
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
    private func failStack(_ fail: PEMachineCore.Fail) -> [(PEMachineCore.Symbols.Index, PEMachineCore.UniText.Index)] {
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
        let uctext = PEMachineCore.uniText(text)
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
    
    func parse(_ symbol: PEMachineCore.Symbols.Index, _ uctext: UniText, trace: Bool = false)->ParseResult {
        let mr = core.parse(symbol, uctext, trace: trace)
        return makeResult(mr, uctext)
    }

    public func parse(_ symName: String, _ uctext: UniText, trace: Bool = false)->ParseResult {
        let sym = symbolIndex(symName)!
        return parse(sym, uctext, trace: trace)
    }
    
    public func printProgram() {
        core.printProgram()
    }

}

#if DEBUG
extension PEMachine.ParseResult.Failure {
    public func printFailure() {
        let lineEnds = text[..<endIndex].indices(of: PEMachineCore.uniChar("\n")).ranges,
            lastLineStart = lineEnds.last?.upperBound
        //print(lineEnds)
        print("parse FAIL",
              //"at", fail.i,
              //"lastLineStart", lastLineStart ?? "nil",
              "line", lineEnds.reduce(1, { partialResult, range in
            partialResult+PEMachineCore.uniString(text[range]).count
        }),
              "char", (PEMachineCore.uniString(text[(lastLineStart ?? text.startIndex)..<endIndex]).count)+1,
              PEMachineCore.failText(text, endIndex) )
        stack.reversed().forEach { (cs: (PEMachineCore.Symbols.Index, PEMachine.UniText.Index)) in
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

extension PEMachine.ParseResult.Success {
    public struct Visit: Sequence, IteratorProtocol {
        private let result: PEMachine.ParseResult.Success
        internal var index: PEMachine.Tree.Index
        public var symbol: PEMachine.Symbols.Element { result.nodeSymbol(index) }
        public var string: String { result.nodeString(index) }
        internal init(result: PEMachine.ParseResult.Success, index: PEMachine.Tree.Index) {
            self.result = result
            self.index = index
        }
        public func visitChildren(calling: (Visit)->Void) {
            let first = result.tree.nodes[index].first
            if first == index { return } // no children
            var childVisit = Visit(result: result, index: first)
            while childVisit.index != /*LAST*/-1 {
                calling(childVisit)
                childVisit.index = result.tree.nodes[childVisit.index].next
            }
        }
        public func mapChildren<T>(calling: (Visit)->T)->[T] {
            let first = result.tree.nodes[index].first
            if first == index { return [] } // no children
            var childVisit = Visit(result: result, index: first),
                mapped = [T]()
            while childVisit.index != /*LAST*/-1 {
                mapped.append(calling(childVisit))
                childVisit.index = result.tree.nodes[childVisit.index].next
            }
            return mapped
        }
        public func mapChildren<T>(_ sym: Symbol, calling: (Visit)->T)->[T]
                                where Symbol: Equatable {
            let first = result.tree.nodes[index].first
            if first == index { return [] } // no children
            var childContext = Visit(result: result, index: first),
                mapped = [T]()
            while childContext.index != /*LAST*/-1 {
                if childContext.symbol == sym {
                    mapped.append(calling(childContext))
                }
                childContext.index = result.tree.nodes[childContext.index].next
            }
            return mapped
        }
        public subscript(child: Int)->Visit {
            var c = result.tree.nodes[index].first,
                skip = child
            if c == index { preconditionFailure("Index out of bounds") } // no children
            while skip > 0 {
                if c == /*LAST*/-1 { preconditionFailure("Index out of bounds") }
                c = result.tree.nodes[c].next
                skip -= 1
            }
            return Visit(result: result, index: c)
        }
        public subscript(child: Symbol)->Visit? where Symbol: Equatable {
            var c = result.tree.nodes[index].first
            if c == index { return nil } // no children
            while c != /*LAST*/-1 {
                if result.nodeSymbol(c) == child {
                    return Visit(result: result, index: c)
                }
                c = result.tree.nodes[c].next
            }
            return nil // not found
        }

        // == Sequence conformance ==
        
        public typealias Element = Visit
        public mutating func next() -> Visit? {
            if index == /*LAST*/-1 { return nil }
            let i = index
            index = result.tree.nodes[index].next
            return Visit(result: result, index: i)
        }
        public func makeIterator() -> Visit {
            precondition(result.tree.nodes[index].first != /*LEAF*/-1)
            return Visit(result: result, index: result.tree.nodes[index].first)
        }

    }
    var rootVisit: Visit { Visit(result: self, index: tree.root) }
}
