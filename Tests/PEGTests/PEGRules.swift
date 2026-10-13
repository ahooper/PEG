//
//  PEGRules.swift
//  PEGTests
//
//  Created by Andy Hooper on 2026-01-21.
//

import Testing
@testable import PEG

struct PEGRules {
    let bg = chpegParse,
        cg = PEMachine(chpegSource)!

    @Test func PEGLexical() async throws {
        
        /*
         Options     { } <- [A-Za-z]*
         Identifier  {L} <- [a-zA-Z_][a-zA-Z_0-9]*
         Literal     {S} <- ['] (!['] Char)* [']
                          / ["] (!["] Char)* ["]
         CharClass   {S} <- '[' (!']' CharRange)+ ']'
         CharRange   { } <- Char '-' !']' Char / Char
         Char        { } <- EscChar / OctChar / PlainChar
         EscChar     {L} <- '\\' [nrt'"\[\]\\]
         OctChar     {L} <- '\\' [0-3][0-7][0-7]
                          / '\\' [0-7][0-7]?
         PlainChar   {L} <- !'\\' .
         PredOp      {L} <- [&!]
         RepOp       {L} <- [*+?]
         Dot         {L} <- '.'

         S           {I} <- ([ \t\r\n]+ / '#' (![\r\n] .)* [\r\n]? )*
         */
        
        for (name, text, tail) in [
            
                // literal
                ("Dot", ".", ""),
                ("Dot", "", nil),
                ("Dot", ".X", "X"),
                
                // sequence, charRanges, repeat0
                ("Identifier", "Z", ""),
                ("Identifier", "9", nil),
                ("Identifier", "", nil),
                ("Identifier", "ab3d", ""),
                ("Identifier", "ab3d '", " '"),

                // sequence, charRanges, repeat0, repeat1, choice, option
                ("S", "", ""),
                ("S", "x", "x"),
                ("S", " ", ""),
                ("S", "  ", ""),
                ("S", "   ", ""),
                ("S", "\t", ""),
                ("S", " \t", ""),
                ("S", " \r", ""),
                ("S", " \n", ""),
                ("S", "\r\n", ""), //NOTE: in Swift "\r\n" is one composite Character!
                ("S", "  \t \r \nX", "X"),
                ("S", "  # abc \nX", "X"),
                ("S", "  # abc ", ""),

                // charRanges
                ("PredOp", "&", ""),
                ("PredOp", "!", ""),
                ("PredOp", "x", nil),
                ("RepOp", "*", ""),
                ("RepOp", "+", ""),
                ("RepOp", "?", ""),
                ("RepOp", "x", nil),

                // anychar
                ("PlainChar", "a", ""),
                ("PlainChar", "\\a", nil),
                ("PlainChar", "", nil),

                // not
                ("EscChar", "\\n", ""),
                ("EscChar", "\\r", ""),
                ("EscChar", "\\t", ""),
                ("EscChar", "\\x", nil),
                ("EscChar", "\\'", ""),
                ("EscChar", "\\\"", ""),
                ("EscChar", ".", nil),
                
                ("Literal", "'tuv'", ""),
                ("Literal", "''", ""),
                ("Literal", "'''", "'"),
                ("Literal", #"'\''"#, ""),
                ("Literal", #""tuv""#, ""),
                ("Literal", #""""#, ""),

                ("OctChar", "\\123", ""),
                ("OctChar", "\\12", ""),
                ("OctChar", "\\1", ""),
                ("OctChar", "\\456", "6"),
                ("OctChar", "456", nil),
                
                // id
                ("Char", "a", ""),
                ("Char", "\\n", ""),
                ("Char", "\\123", ""),
                ("Char", "", nil),
                
                ("CharClass", "[a-zA-Z_]", ""),
                ("CharClass", "[a-zA-Z_]", ""),
                ("CharClass", "[a]", ""),
                ("CharClass", "[", nil),

                // no rules in Grammar use test

                ] {
            bg.testCase(name == "S" ? "_S" : name, text, tail)
            cg.testCase(name, text, tail)
        }
    }

    @Test func PEGHeirarchical() async throws {
                
        /*
        Grammar     {S} <- S Definition+ !.
        Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
        Choice      { } <- Sequence ('/' S Sequence)*
        Sequence    { } <- Predicate+
        Predicate   { } <- (PredOp S)? Repeat
        Repeat      { } <- Primary (RepOp S)?
        Primary     { } <- Identifier S ![{<]
                         / '(' S Choice ')' S
                         / Literal S
                         / CharClass S
                         / Dot S
        */
        
        for (name, text, tail) in [
            
                //    Primary     { } <- Identifier S ![{<]
                //                     / '(' S Choice ')' S
                //                     / Literal S
                //                     / CharClass S
                //                     / Dot S
                ("Primary", "identifier", ""),
                ("Primary", "identifier    ", ""),
                ("Primary", "identifier  \t\n", ""),
                ("Primary", "identifier <-   ", nil),
                ("Primary", "identifier {} <-   ", nil),
                ("Primary", "'literal'", ""),
                ("Primary", "'literal'  \t\n", ""),
                ("Primary", "[a]", ""),
                ("Primary", "[a-z]", ""),
                ("Primary", "[aa-z]", ""),
                ("Primary", "[aa-zA-Z-_]", ""),
                ("Primary", "[a]   ", ""),
                ("Primary", ". ", ""),
                ("Primary", "( a / B )    ", ""),
                ("Primary", "( a / B     ", nil),
                ("Primary", "a   \t\n", ""),
                ("Primary", "'s' \n", ""),
                ("Primary", "", nil),

                //    Repeat      { } <- Primary (RepOp S)?
                ("Repeat", "a", ""),
                ("Repeat", "a+", ""),
                ("Repeat", "a*", ""),
                ("Repeat", "a?", ""),
                ("Repeat", "a? ", ""),
                ("Repeat", "a/ ", "/ "),
                
                //    Predicate   { } <- (PredOp S)? Repeat
                ("Predicate", "a", ""),
                ("Predicate", "&a", ""),
                ("Predicate", "!a", ""),
                ("Predicate", "!  a*", ""),
                ("Predicate", "!  ", nil),

                //    Sequence    { } <- Predicate+
                ("Sequence", "a", ""),
                ("Sequence", "a b c / d", "/ d"),
                ("Sequence", "a b c (", "("),

                //    Choice      { } <- Sequence ('/' S Sequence)*
                ("Choice", "a b c", ""),
                ("Choice", "a / c", ""),
                ("Choice", "a b / c", ""),
                ("Choice", "a b /", "/"),
                ("Choice", "a b / c d / e f", ""),

                //    Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
                ("Definition", "q<-'s'", ""),
                ("Definition", "q{x}<-'s'", ""),
                ("Definition", "q <- 's' / a / b", ""),

                //    Grammar     {S} <- S Definition+ !.
                ("Grammar", #"""
                            Grammar     {S} <- S Definition+ !.
                            Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
                            Choice      { } <- Sequence ('/' S Sequence)*
                            Sequence    { } <- Predicate+
                            Predicate   { } <- (PredOp S)? Repeat
                            Repeat      { } <- Primary (RepOp S)?
                            Primary     { } <- Identifier S ![{<]
                                             / '(' S Choice ')' S
                                             / Literal S
                                             / CharClass S
                                             / Dot S
                            """#, ""),

                ] {
            bg.testCase(name, text, tail)
            cg.testCase(name, text, tail)
        }
    }

}
