//
//  testLeftRecurs.swift
//  PEG
//
//  Created by Andy Hooper on 2026-10-12.
//

import Testing
@testable import PEG

struct testLeftRecurs {

    @Test func chpegLR1() {
        let pm = PEMachine("""
            a <- a* 'a' / 'b'
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR2() {
        let pm = PEMachine("""
            A <- (B/C)
            B <- (&"b"/C) A
            C <- B
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR3() {
        let pm = PEMachine("""
            # src: https://github.com/PhilippeSigaud/Pegged/wiki/Left-Recursion
            # A more subtle form of the same problem is that the recursive element is hidden behind other elements that can succeed without consuming input, like an optional:

                E <- F? E '+n' / 'n'

            # additions needed for undefined Idents

                F <- 'f'
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR4() {
        let pm = PEMachine("""
            # src: https://github.com/PhilippeSigaud/Pegged/wiki/Left-Recursion
            # Hidden left-recursion can even be more obscured. Consider this:

                    E <- F E '+n' / 'n'
                    F <- A B C / D*

            # Because D* matches the empty string, F succeeds without consuming input, and hides left-recursion in E. You can imagine that there is no end to how deep left-recursion can be hidden in your grammar.

            # additions needed for undefined Idents
            A<-'a'
            B<-'b'
            C<-'c'
            D<-'d'
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR5() {
        let pm = PEMachine("""
            # src: https://github.com/PhilippeSigaud/Pegged/wiki/Left-Recursion
            #
            #Indirect Left-Recursion
            #We've seen that direct left-recursion happens when E calls into itself on the same input. Indirect left-recursion happens when E as its first step calls any number of other rules, that at one or more points call back into E with the same input. For example:

                E <- F '+n' / 'n'
                F <- G H / J
                J <- K / E L

            # additional defs needed

                G <- 'g'
                H <- 'h'
                K <- 'k'
                L <- 'l'
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR6() {
        let pm = PEMachine("""
            # src: https://github.com/PhilippeSigaud/Pegged/wiki/Left-Recursion
            #
            #Interlocking cycles
            #It can yet be more complicated. For inputs like nlm-n+(aaa)n, this grammar has several interlocking left-recursive cycles:

                    S <- E eoi
                    E <- F 'n' / 'n'
                    F <- E '+' I* / G '-'
                    G <- H 'm' / E
                    H <- G 'l'
                    I <- '(' A+ ')'
                    A <- 'a'

            # additional defs needed

            eoi <- !.
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR7() {
        let pm = PEMachine("""
            # src: https://github.com/PhilippeSigaud/Pegged/wiki/Left-Recursion
            # Another example: two rules that are mutually left-recursive.

                M <- L eoi
                L <- P '.x' / 'x'
                P <- P '(n)' / L

            # additional defs needed

                eoi <- !.
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR8() {
        let pm = PEMachine("""
            A<-(B/C) B<-(&"b"/C)A C<-B 
            """)
        #expect(pm == nil)
    }

    @Test func chpegLR9() {
        let pm = PEMachine("""
            A<-(B/C) B<-(&"b"/C)A C<-B D<-(&"d")*
            """)
        #expect(pm == nil)
    }
    
    @Test func peglibLeft_recursive_test() {
        let pm = PEMachine("""
            A <- A 'a'
            B <- A 'a'
            """)
        #expect(pm == nil)
    }
    
    @Test func peglibLeft_recursive_with_option_test() {
        let pm = PEMachine("""
            A  <- 'a' / 'b'? B 'c'
            B  <- A
            """)
        #expect(pm == nil)
    }
    
    @Test func peglibLeft_recursive_with_zom_test() {
        let pm = PEMachine("""
            A <- 'a'* A*
            """)
        #expect(pm == nil)
    }
    
    @Test func peglibLeft_recursive_with_a_ZOM_content_rule() {
        let pm = PEMachine("""
            A <- B
            B <- _ A
            _ <- ' '* # Zero or more
            """)
        #expect(pm == nil)
    }
    
    @Test func peglibRecursive_with_prefix_test() {
        let pm = PEMachine("""
            A <- 'prefix' A / 'x'
            """)
        #expect(pm != nil)
    }
    
    @Test func pegliIndirect_left_recursion_test() {
        let pm = PEMachine("""
            A <- B 'a'
            B <- C 'b'
            C <- A 'c' / 'd'
            """)
        #expect(pm == nil)
    }
    
    @Test func pegliComplex_indirect_left_recursion_test() {
        let pm = PEMachine("""
            A <- B / C 'a'
            B <- D 'b'
            C <- E 'c'
            D <- A 'd'
            E <- F 'e'
            F <- G 'f'
            G <- A 'g' / 'h'
            """)
        #expect(pm == nil)
    }
    
    @Test func peglibMutual_left_recursion_test() {
        let pm = PEMachine("""
            A <- B 'x' / 'a'
            B <- A 'y'
            """)
        #expect(pm == nil)
    }
    
    @Test func peglibHidden_left_recursion_with_epsilon_test() {
        let pm = PEMachine("""
            A <- B A / 'a'
            B <- 'b'?
            """)
        #expect(pm == nil)
    }

    @Test func peglibDeep_indirect_epsilon_test() {
      // LR through a chain of rules with a nullable prefix
      let pm = PEMachine("""
            A <- B
            B <- C
            C <- D? A / 'x'
            D <- 'x'
        """)
        #expect(pm == nil)
    }

    @Test func peglibPredicate_epsilon_test() {
      // &B is always nullable (predicates don't consume)
      let pm = PEMachine("""
            A <- &B A / 'a'
            B <- 'b'?
        """)
        #expect(pm == nil)
    }

    @Test func peglibComplex_choice_epsilon_test() {
      // D <- '' makes D? A nullable prefix
      let pm = PEMachine("""
            A <- B / C
            B <- D? A 'x'
            C <- 'y'
            D <- ''
        """)
        #expect(pm == nil)
    }

    @Test func peglibComplex_sequence_epsilon_test() {
      // Multiple nullable prefixes before the recursive reference
      let pm = PEMachine("""
            A <- B C D A / 'a'
            B <- 'b'?
            C <- 'c'*
            D <- ''
        """)
        #expect(pm == nil)
    }

    @Test func peglibCross_reference_epsilon_test() {
      // B is nullable through a chain of nullable rules (C->E->'e'?, D->F->'f'*)
      // PEG ordered choice: B tries C first, C=E='e'? always succeeds (empty),
      // so D is never reached. B effectively always matches empty.
      let pm = PEMachine("""
            A <- B A / 'a'
            B <- C / D
            C <- E
            D <- F
            E <- 'e'?
            F <- 'f'*
        """)
        #expect(pm == nil)
    }

    @Test func peglibPure_epsilon_left_recursion_test() {
      // A <- A / '' — most dangerous pattern, should not hang
      let pm = PEMachine("""
            A <- A / ''
        """)
        #expect(pm == nil)
    }

    @Test func peglibDirect_left_recursion_no_alternatives_test() {
      // A <- A — no base case, can never match
      let pm = PEMachine("""
            A <- A
        """)
        #expect(pm == nil)
    }

    @Test func peglibMutual_recursion_with_epsilon_test() {
      let pm = PEMachine("""
            A <- B / ''
            B <- A / 'x'
        """)
        #expect(pm == nil)
    }

    @Test func peglibDiamond_dependency_epsilon_test() {
      // Both B and C reference A through nullable D
      let pm = PEMachine("""
            A <- B / C
            B <- D A 'b'
            C <- D A 'c'
            D <- 'x'?
        """)
        #expect(pm == nil)
    }

    @Test func peglibClass_epsilon_test() {
      // [a-z]? is nullable, so A is left-recursive through it
      let pm = PEMachine("""
            A <- [a-z]? A / 'x'
        """)
        #expect(pm == nil)
    }

    @Test func peglibEpsilon_with_complex_predicate_test() {
      // &B succeeds (B='', always matches), !C succeeds when C fails
      let pm = PEMachine("""
            A <- &B !C A / 'a'
            B <- ''
            C <- 'c'?
        """)
        #expect(pm == nil)
    }

    // ---------------------------------------------------------------------------
    // Arithmetic expressions with semantic values
    // ---------------------------------------------------------------------------

    @Test func peglibArithmeticExpressions() {
        let pm = PEMachine("""
          expr <- expr '+' term / expr '-' term / term
          term <- term '*' factor / term '/' factor / factor
          factor <- '(' expr ')' / number
          number <- [0-9]+
          """)
          #expect(pm == nil)
    }

    // ---------------------------------------------------------------------------
    // Non-LR regression (right-recursive expression, should not break with LR on)
    // ---------------------------------------------------------------------------

    @Test func peglibRightRecursiveExpressionRegression() {
      let pm = PEMachine("""
            Expression  <- Term ('+' / '-') Expression / Term
            Term        <- Factor ('*' / '/') Term / Factor
            Factor      <- '(' Expression ')' / Number
            Number      <- [0-9]+
        """)
         #expect(pm != nil)
    }

    @Test func peglibTypeScriptTypes_realistic() {
      let pm = PEMachine("""
            Type           <- UnionType / IntersectionType / PrimaryType
            UnionType      <- UnionType '|' IntersectionType / IntersectionType
            IntersectionType <- IntersectionType '&' PrimaryType / PrimaryType
            PrimaryType    <- BasicType / ObjectType / FunctionType / '(' Type ')'
            ObjectType     <- '{' PropertyList '}'
            PropertyList   <- Property (',' Property)* / ''
            Property       <- Identifier ':' Type
            FunctionType   <- '(' ParameterList ')' '=>' Type
            ParameterList  <- Type (',' Type)* / ''
            BasicType      <- 'string' / 'number' / 'boolean'
            Identifier     <- [a-zA-Z][a-zA-Z0-9]*
        """)
        #expect(pm == nil)
    }


}
