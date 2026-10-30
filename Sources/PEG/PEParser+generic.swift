//
//  PEParser+generic.swift
//  PEGHighlight
//
//  Created by Andy Hooper on 2026-10-03.
//

extension PEParser {
    
    init<Symbol>(rules: [Symbol: Op])
                    where Symbol: RawRepresentable,
                          Symbol.RawValue == SymbolRaw,
                          Symbol: CaseIterable {
        let symbols = Symbol.allCases
        self.init(symbols: symbols.map {String(describing: $0) },
                   rules: symbols.map { rules[$0]! })
    }
    
    public func parse<Symbol>(_ symbol: Symbol, _ text: String)->Result<Symbol>
                    where Symbol: RawRepresentable,
                          Symbol.RawValue == SymbolRaw,
                          Symbol: CaseIterable {
        let t = PEParser.uniText(text)
        let r = parse(symbol.rawValue, t)
        switch r {
        case let .success(s):
            return .success(Result<Symbol>.Success(text: t, endIndex: s.endIndex,
                                                   tree: s.tree, symbols: [Symbol](Symbol.allCases)))
        case let .failure(f):
            #if DEBUG
            return .failure(Result<Symbol>.Failure(text: t, endIndex: f.endIndex,
                                                   stack: f.stack, symbols: [Symbol](Symbol.allCases)))
            #else
            return .failure(Result<Symbol>.Failure())
            #endif
        }
    }
    
    public func parse(_ symbol: String, _ text: String)->Result<String> {
        parse(symbols.firstIndex(of: symbol)!, Self.uniText(text))
    }

    func parse(_ symbol: SymbolRaw, _ text: UniText)->Result<String> {
        var res = State(tree: Tree(), callNest: 0, callStack: [])
        res.callStack.reserveCapacity(100)
        let mark = res.tree.mark
        if let r = rules[symbol].parse(text, text.startIndex, &res) {
            res.tree.end(symbol, mark, text.startIndex..<r)
            //tree.printTree(symbols: symbols)
            return .success(Result<String>.Success(text: text,
                                                   endIndex: r,
                                                   tree: res.tree,
                                                   symbols: symbols))
        } else {
            res.tree.discard(mark)
            #if DEBUG
            return .failure(Result<String>.Failure(text: text,
                                                   endIndex: text.startIndex,
                                                   stack: res.furthestFail?.stack.map { ($0.symRaw, $0.index )} ?? [],
                                                   symbols: symbols))
            #else
            return .failure(Result<String>.Failure())
            #endif
        }
    }

    public enum Result<Symbol> {
        public struct Success {
            public let text: UniText,
                       endIndex: UniText.Index,
                       tree: Tree,
                       symbols: [Symbol]
            public func nodeText(_ index: Tree.Index)->UniText.SubSequence {
                text[tree[index].value]
            }
            public func nodeString(_ index: Tree.Index)->String {
                PEParser.uniString(UniText(nodeText(index)))
            }
            public func nodeSymbol(_ index: Tree.Index)->Symbol {
                symbols[tree[index].identifier]
            }
            public func nodeId(_ index: Tree.Index)->Int {
                tree[index].identifier
            }
            var rootVisit: Visit { Visit(result: self, index: tree.root) }
        }
        public struct Failure {
            #if DEBUG
            public let text: UniText,
                       endIndex: UniText.Index,
                       stack: [([Symbol].Index, UniText.Index)],
                       symbols: [Symbol]
            #endif
        }
        case success(Success)
        case failure(Failure)
        
        public struct Visit: Sequence, IteratorProtocol {
            private let result: Success
            internal var index: Tree.Index
            public var symbol: Symbol { result.nodeSymbol(index) }
            public var string: String { result.nodeString(index) }
            internal init(result: Success, index: Tree.Index) {
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

    }
}

extension PEParser.Ref {
    convenience init<Symbol>(_ ref: Symbol)
                    where Symbol: RawRepresentable,
                    Symbol.RawValue == PEParser.SymbolRaw {
        self.init(ref.rawValue)
    }
}

