//
//  chpegParser.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-22.
//

/*  chpeg grammar from https://github.com/ChrisHixon/chpeg/blob/master/grammars/chpeg.chpeg
    Copyright (c) 2022, Christopher Hixon
    https://github.com/ChrisHixon/chpeg/blob/master/LICENSE.txt
    # Extended PEG grammar for chpeg bytecode parser/compiler, defined in its own grammar.
    #
    # The effective grammar is the same as the original PEG grammar from
    # Bryan Ford's paper, but with Options added in front of <- to guide parse tree building.
    #
    # This grammar is optimized for chpeg and generates the AST the compiler expects

    # Hierarchical syntax
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

    # Lexical syntax
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

#if false
public enum chpegSymbol: Int, CaseIterable, Sendable {
    case
        Grammar,
        Definition,
        Choice,
        Sequence,
        Predicate,
        Repeat,
        Primary,
        Options,
        Identifier,
        Literal,
        CharClass,
        CharRange,
        Char,
        EscChar,
        OctChar,
        PlainChar,
        PredOp,
        RepOp,
        Dot,
        _S
}
#endif
//TODO: UniChar <- '\\x' [0-9a-fA-F] [0-9a-fA-F]
//               / '\\u' [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]
//               / '\\U' [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]
extension PEParser {
    nonisolated(unsafe) public static let chpeg = PEParser.chpegParser()
    static func chpegParser()->PEParser {
        let rules: [chpegSymbol: Op] = [
            // # Hierarchical syntax
            
            // Grammar     {S} <- S Definition+ !.
            .Grammar:
                Seq(
                    Ref(chpegSymbol._S),
                    Rep1(
                        Ref(chpegSymbol.Definition)
                    ),
                    Not(Any1())
                ),
            // Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
            .Definition:
                Seq(
                    Ref(chpegSymbol.Identifier),
                    Ref(chpegSymbol._S),
                    Opt(
                        Seq(
                            Chr("{"),
                            Ref(chpegSymbol._S),
                            Ref(chpegSymbol.Options),
                            Ref(chpegSymbol._S),
                            Chr("}"),
                            Ref(chpegSymbol._S),
                        )
                    ),
                    Lit("<-"),
                    Ref(chpegSymbol._S),
                    Ref(chpegSymbol.Choice),
                ),
            // Choice      { } <- Sequence ('/' S Sequence)*
            .Choice:
                Seq(
                    Ref(chpegSymbol.Sequence),
                    Rep(
                        Seq(
                            Chr("/"),
                            Ref(chpegSymbol._S),
                            Ref(chpegSymbol.Sequence),
                        )
                    )
                ),
            // Sequence    { } <- Predicate+
            .Sequence:
                Rep1(Ref(chpegSymbol.Predicate)),
            // Predicate   { } <- (PredOp S)? Repeat
            .Predicate:
                Seq(
                    Opt(
                        Seq(
                            Ref(chpegSymbol.PredOp),
                            Ref(chpegSymbol._S),
                        )
                    ),
                    Ref(chpegSymbol.Repeat)
                ),
            // Repeat      { } <- Primary (RepOp S)?
            .Repeat:
                Seq(
                    Ref(chpegSymbol.Primary),
                    Opt(
                        Seq(
                            Ref(chpegSymbol.RepOp),
                            Ref(chpegSymbol._S),
                        )
                    )
                ),
            // Primary     { } <- Identifier S ![{<]
            //                  / '(' S Choice ')' S
            //                  / Literal S
            //                  / CharClass S
            //                  / Dot S
            .Primary:
                Alt(
                    Seq(
                        Ref(chpegSymbol.Identifier),
                        Ref(chpegSymbol._S),
                        Not(ChrSet("{<"))
                    ),
                    Seq(
                        Chr("("),
                        Ref(chpegSymbol._S),
                        Ref(chpegSymbol.Choice),
                        Chr(")"),
                        Ref(chpegSymbol._S),
                    ),
                    Seq(
                        Ref(chpegSymbol.Literal),
                        Ref(chpegSymbol._S),
                    ),
                    Seq(
                        Ref(chpegSymbol.CharClass),
                        Ref(chpegSymbol._S),
                    ),
                    Seq(
                        Ref(chpegSymbol.Dot),
                        Ref(chpegSymbol._S),
                    ),
                ),
            
            // # Lexical syntax
            
            // Options     { } <- [A-Za-z]*
            .Options:
                SpanSet("A"..."Z", "a"..."z"),
            // Identifier  {L} <- [a-zA-Z_][a-zA-Z_0-9]*
            .Identifier:
                Seq(
                    ChrSet("A"..."Z", "a"..."z", "_"..."_"),
                    SpanSet("A"..."Z", "a"..."z", "_"..."_", "0"..."9")
                ),
            // Literal     {S} <- ['] (!['] Char)* [']
            //                  / ["] (!["] Char)* ["]
            .Literal:
                Alt(
                    Seq(
                        Chr("'"),
                        Rep(
                            Seq(
                                Not(Chr("'")),
                                Ref(chpegSymbol.Char)
                            )
                        ),
                        Chr("'"),
                    ),
                    Seq(
                        Chr("\""),
                        Rep(
                            Seq(
                                Not(Chr("\"")),
                                Ref(chpegSymbol.Char)
                            )
                        ),
                        Chr("\""),
                    )
                ),
            // CharClass   {S} <- '[' (!']' CharRange)+ ']'
            .CharClass:
                Seq(
                    Chr("["),
                    Rep1(
                        Seq(
                            Not(Chr("]")),
                            Ref(chpegSymbol.CharRange)
                        )
                    ),
                    Chr("]"),
                ),
            // CharRange   { } <- Char '-' !']' Char / Char
            .CharRange:
                Alt(
                    Seq(
                        Ref(chpegSymbol.Char),
                        Chr("-"),
                        Not(Chr("]")),
                        Ref(chpegSymbol.Char),
                    ),
                    Ref(chpegSymbol.Char),
                ),
            // Char        { } <- EscChar / OctChar / PlainChar
            .Char:
                Alt(
                    Ref(chpegSymbol.EscChar),
                    Ref(chpegSymbol.OctChar),
                    Ref(chpegSymbol.PlainChar),
                ),
            // EscChar     {L} <- '\\' [nrt'"\[\]\\]
            .EscChar:
                Seq(
                    Chr("\\"),
                    ChrSet("nrt'\"[]\\"),
                ),
            // OctChar     {L} <- '\\' [0-3][0-7][0-7]
            //                  / '\\' [0-7][0-7]?
            .OctChar:
                Alt(
                    Seq(
                        Chr("\\"),
                        ChrRange("0","3"),
                        ChrRange("0","7"),
                        ChrRange("0","7"),
                    ),
                    Seq(
                        Chr("\\"),
                        ChrRange("0","7"),
                        Opt(ChrRange("0","7")),
                    ),
                ),
            // PlainChar   {L} <- !'\\' .
            .PlainChar:
                Seq(
                    Not(Chr("\\")),
                    Any1()
                ),
            // PredOp      {L} <- [&!]
            .PredOp:
                ChrSet("&!"),
            // RepOp       {L} <- [*+?]
            .RepOp:
                ChrSet("*+?"),
            // Dot         {L} <- '.'
            .Dot:
                Chr("."),
            // S           {I} <- ([ \t\r\n]+ / '#' (![\r\n] .)* [\r\n]? )*
            ._S:
                Rep(
                    Alt(
                        Seq(
                            ChrSet(" \t\n\r"), // order matters, String considers \r\n a single character!
                            SpanSet(" \t\n\r") // order matters, String considers \r\n a single character!
                        ),
                        Seq(
                            Chr("#"),
                            Rep(
                                Seq(
                                    Not(
                                        ChrSet("\n\r")
                                    ),
                                    Any1()
                                )
                            ),
                            Opt(
                                ChrSet("\n\r")
                            )
                        )
                    )
                )
        ]
        return PEParser(symbols: chpegSymbol.allCases.map {String(describing: $0)},
                        rules: chpegSymbol.allCases.map { rules[$0]! })
    }
}
