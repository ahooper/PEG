//
//  PEMachine+check.swift
//  PEG
//
//  Created by Andy Hooper on 2026-10-11.
//

extension PEMachine.Builder {
    
    private class List<Value> {
        // Crude linked list sufficient only for this use
        public let value: Value
        public let tail: List<Value>?
        init(_ value: Value, _ next: List<Value>?) {
            self.value = value
            self.tail = next
        }
        func contains(_ value: Value)->Bool where Value:Equatable {
            self.value == value || tail?.contains(value) ?? false
        }
        func toArray()->[Value] {
            CollectionOfOne(value) + (tail?.toArray() ?? [])
        }
    }
    
    mutating func checkLeftRecursion(_ parse: PEMachine<chpegSymbol>.ParseResult.Success) {
        // Collect definitions
        var def: [String: PEMachine<chpegSymbol>.Tree.Index] = [:]
        if case .Grammar = parse.nodeSymbol(parse.tree.root),
           var grammarCI = parse.tree.childIndices(parse.tree.root) {
            while let di = grammarCI.next() {
                if case .Definition = parse.nodeSymbol(di),
                   var defCI = parse.tree.childIndices(di),
                    let idx = defCI.opt(chpegSymbol.Identifier) {
                    _ = defCI.opt(chpegSymbol.Options)
                    let defx = defCI.opt(chpegSymbol.Choice)!
                    let id = parse.nodeString(idx)
                    if def[id] != nil {
                        errors.append("Multiple definitions of \(id)")
                    }
                    def[id] = defx
                } else {
                    assertionFailure("Grammar unexpected \(parse.nodeSymbol(di))")
                }
            }
        } else {
            assertionFailure("Expected .Grammar")
        }
        
        for id in def.keys {
            let c = check(def[id]!, .init(id, nil))
            if c.recurs != nil {
                errors.append("\(id) is left recusive \(c.recurs!.toArray().reversed().map{String(describing:$0)}.joined(separator: " "))")
            }
        }
        
        func check(_ ti: PEMachine<chpegSymbol>.Tree.Index,
                   _ visited: List<String>?)->(nulls:Bool, recurs:List<String>?) {
            var children = parse.tree.childIndices(ti)!
            switch parse.nodeSymbol(ti) {
            case .Choice:
                //    Choice      { } <- Sequence ('/' S Sequence)*
                var anyn = false
                for alti in children {
                    let c = check(alti, visited)
                    if c.1 != nil { return (true, c.recurs) }
                    if c.0 { anyn = true }
                }
                return (anyn, nil)
            case .Sequence:
                //    Sequence    { } <- Predicate+
                for pi in children {
                    let c = check(pi, visited)
                    if c.recurs != nil { return (true, c.recurs) }
                    if !c.nulls { return c }
                }
                return (true, nil)
            case .Predicate:
                //    Predicate   { } <- (PredOp S)? Repeat
                if let opx = children.opt(chpegSymbol.PredOp) {
                    //    PredOp      {L} <- [&!]
                    let rep = children.next()!
                    switch parse.nodeString(opx) {
                    case "&":
                        return (true, check(rep, visited).recurs)
                    case "!":
                        return (true, check(rep, visited).recurs)
                    default:
                        assertionFailure("Predicate operator found \(parse.nodeString(opx).debugDescription)")
                        return (true, visited)
                    }
                } else {
                    return check(children.next()!, visited)
                }
            case .Repeat:
                //    Repeat      { } <- Primary (RepOp S)?
                let prim = children.next()!
                if let opx = children.opt(chpegSymbol.RepOp) {
                    //    RepOp       {L} <- [*+?]
                    switch parse.nodeString(opx) {
                    case "*":
                        return (true, check(prim, visited).recurs)
                    case "+":
                        return check(prim, visited)
                    case "?":
                        return (true, check(prim, visited).recurs)
                    default:
                        assertionFailure("Repeat operator found \(parse.nodeString(opx).debugDescription)")
                        return (true, visited)
                    }
                } else {
                    return check(prim, visited)
                }
            case .Primary:
                //    Primary     { } <- Identifier S ![{<]
                //                     / '(' S Choice ')' S
                //                     / Literal S
                //                     / CharClass S
                //                     / Dot S
                if let idx = children.opt(chpegSymbol.Identifier) {
                    //    Identifier  {L} <- [a-zA-Z_][a-zA-Z_0-9]*
                    let id = parse.nodeString(idx)
                    if visited?.contains(id) ?? false { return (true, visited!) }
                    if let d = def[id] {
                        return check(d, .init(id, visited))
                    } else {
                        errors.append("Undefined symbol \(parse.nodeString(idx))")
                        return (true, visited)
                    }
                } else if let choicex = children.opt(chpegSymbol.Choice) {
                    return check(choicex, visited)
                } else if let litx = children.opt(chpegSymbol.Literal) {
                    //    Literal     {S} <- ['] (!['] Char)* [']
                    //                     / ["] (!["] Char)* ["]
                    if let charx = parse.tree.childIndices(litx),
                       !charx.filter({parse.tree[$0].has(chpegSymbol.Char)}).isEmpty {
                        return (false, nil)
                    } else {
                        // empty
                        return (true, nil)
                    }
                } else if let classx = children.opt(chpegSymbol.CharClass) {
                    //    CharClass   {S} <- '[' (!']' CharRange)+ ']'
                    return (false, nil)
                } else if let _ = children.opt(chpegSymbol.Dot) {
                    //    Dot         {L} <- '.'
                    return (false, nil)
                } else {
                    assertionFailure("Primary expected Identifier, Choice, Literal, CharClass or Dot")
                    return (true, visited)
                }
            default:
                assertionFailure("\(parse.nodeSymbol(ti)) should not be visited")
                return (true, visited)
            }
        }

    }
    
}
