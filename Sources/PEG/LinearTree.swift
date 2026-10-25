//
//  LinearTree.swift
//  pgen
//
//  Created by Andy Hooper on 2026-08-29.
//

#if DEBUG
import class Foundation.NSString // String(format:,...)
#endif

public struct LinearTree<Identifier:Equatable,Value> {
    /*
     Linear tree nodes are stored in an array in bottom-up order, all cildren
     before the parent (as in post-order traversal). Nodes are constructed in
     post-order with fields to facilitate traversal.
                   index first next
              ┌C1    0     ⁃    1
              ├C2    1     ⁃    2
              ├C3    2     ⁃   LAST
           ┌B1┘      3     0    5
           │  ┌C4    4     ⁃   LAST
           ├B2┘      5     4   LAST
         A1┘         6     3   LAST
     When a branch is added, `next` holds the start index of its subtree (the
     first child). When its parent branch is added, the `next` fields of the
     children are replaced with the index of the next child at their level.
     
     For PEG parsing, this linearized tree is much faster to build than a
     structured tree, such as
         enum Tree {
             case leaf(name:Identifier, value:Value)
             case branch(name:Identifier, children:[Tree])
         }
     
     With PEG backtracking, the tree is frequently rebuilt in place. There is
     benefit in not keeping the node storage allocation tight to the current
     tree contents. `nodesMax` tracks the highest node index ever added, while
     `nodesLast` is the index of the last node built.
     */
    public struct Node {
        public let identifier:Identifier, value:Value, first:Index, next:Index
        
        public func has(_ identifier:Identifier)->Bool {
            self.identifier == identifier
        }
        public func has<Symbol>(_ symbol: Symbol)->Bool
                                where Symbol: RawRepresentable,
                                      Symbol.RawValue == Identifier {
            self.identifier == symbol.rawValue
        }
    }
    public typealias NodeArray = Array<Node>
        // Array seems unexpectedly to have a slight performance edge over ContiguousArray
    public typealias Index = NodeArray.Index
    internal var nodes: NodeArray,
                 nodesMax: Index,
                 nodesLast: Index
    public init() {
        nodes = NodeArray()
        nodes.reserveCapacity(100)
        nodesMax = Index(nodes.count - 1)
        nodesLast = Index(-1)
    }
    
    public subscript(_ index: Index)->Node { nodes[index] }
    
    // == Building ==
    
    /// `next` sentinel value for last child
    // static let LAST = -1 // Static stored properties not supported in generic types
    /// `first` sentinel value for no children
    // static let LEAF = -1 // Static stored properties not supported in generic types
   
    /// Record the start of a new node
    public typealias Mark = Index
    public var mark: Mark { nodesLast + 1 }
    
    /// Close a new node
    public mutating func end(_ identifier: Identifier, _ begin: Mark, _ value: Value) {
        //print(nodes.endIndex, "end", identifier, begin, value)
        assert(begin <= nodes.endIndex)
        // Link children for left-to-right traversal.
        // When a branch is added, `next` holds the start index of its subtree (the
        // first child). When its parent branch is added, the `next` fields of the
        // children are replaced with the index of the next child at their level.
        var child = nodesLast,
            next = /*LAST*/-1
        while child >= begin {
            let cn = nodes[child]
            //print("      ", child, cn.identifier, cn.value, "next", next)
            if cn.first == child {
                // leaf
                nodes[child] = Node(identifier: cn.identifier, value: cn.value, first: cn.first, next: next)
                next = child
                child = nodes.index(before: child)
            } else {
                // branch
                nodes[child] = Node(identifier: cn.identifier, value: cn.value, first: cn.first, next: next)
                next = child
                child = nodes.index(before: cn.next)
            }
        }
        let first = (next <= nodesLast) ? next
                                        : /*LEAF*/-1 // no children
        if nodesLast < nodesMax {
            nodesLast += 1
            nodes[nodesLast] = Node(identifier: identifier, value: value, first: first, next: begin)
        } else {
            nodes.append(Node(identifier: identifier, value: value, first: first, next: begin))
            nodesMax = nodes.count - 1
            nodesLast = nodesMax
        }
    }
    
    /// Discard a subtree being built
    public mutating func discard(_ begin: Mark) {
        assert(begin <= nodes.endIndex)
        nodesLast = begin - 1
    }
        
    // == Traversal ==
    
    public var root: Index { nodes.index(before: nodes.endIndex) }
    
    public struct IndexIterator: Sequence, IteratorProtocol {
        public typealias Element = Index
        let nodes: NodeArray
        var _next: Index
        init(nodes: NodeArray, _next: Index) {
            self.nodes = nodes
            self._next = _next
        }
        init(_ tree: LinearTree) {
            self.nodes = tree.nodes
            self._next = tree.root
        }
        public mutating func next() -> Index? {
            if _next == /*LAST*/-1 { return nil }
            let n = _next
            _next = nodes[n].next
            return n
        }
        
        public func peek()->Node? {
            return if _next == /*LAST*/-1 { nil }
            else { nodes[_next] }
        }
        
        public mutating func opt(_ identifier: Identifier)->Index? {
            if peek()?.has(identifier) ?? false {
                return next()
            }
            return nil
        }
        
        public mutating func opt<Symbol>(_ symbol: Symbol)->Index?
                                where Symbol: RawRepresentable,
                                      Symbol.RawValue == Identifier {
            if peek()?.has(symbol.rawValue) ?? false {
                return next()
            }
            return nil
        }
        
        public func filter(_ identifier: Identifier)->LazyFilterSequence<LazySequence<IndexIterator>.Elements> {
            lazy.filter { e in nodes[e].has(identifier) }
        }

    }
    
    public func childIndices(_ index: Index)->IndexIterator? {
        let n = nodes[index]
        return if n.first == /*LEAF*/-1 { nil } // no children
               else { IndexIterator(nodes: nodes, _next: n.first) }
    }

    // == Printing ==
        
    public func printTree<Symbols>(symbols: Symbols) where Symbols: Collection,
                                                    Symbols.Index == Identifier {
        func printTree(_ index: Index, depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            let n = nodes[index]
            Swift.print(indent+String(describing:  symbols[n.identifier]),
                    index, n.first, n.next, n.value)
            childIndices(index)?.forEach { printTree($0, depth: depth+1) }
        }
        printTree(root, depth: 0)
    }
    #if DEBUG
    func printNodes() {
        Swift.print("Index First  Next Identifier Value")
        for i in nodes.indices {
            let n = nodes[i]
                Swift.print(String(format: "%5ld %5ld %5ld %@ %@",
                                   i, n.first, n.next,
                                   String(describing: n.identifier),
                                   String(describing: n.value)))
        }
    }
    #endif

}
