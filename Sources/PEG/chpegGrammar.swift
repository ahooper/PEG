//
//  chpegGrammar.swift
//  pgen
//
//  Created by Andy Hooper on 2026-09-22.
//

//  https://github.com/ChrisHixon/chpeg/blob/master/grammars/chpeg.chpeg
//  Copyright (c) 2022, Christopher Hixon
//  https://github.com/ChrisHixon/chpeg/blob/master/LICENSE.txt

public let chpegSource = #"""
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
"""#
//#TODO: UniChar     {L} <- '\\x' [0-9a-fA-F] [0-9a-fA-F]
//#                       / '\\u' [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]
//#                       / '\\U' [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]

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
let chpegGrammar: PEMachine<chpegSymbol>.Builder.Bootstrap = [
    // # Hierarchical syntax
    
    // Grammar     {S} <- S Definition+ !.
    .Grammar:
                .seq([
                    .call(._S),
                    .rep1(
                        .call(.Definition)
                        ),
                    .not(.any(1))
                    ]),
    // Definition  { } <- Identifier S ('{' S Options S '}' S)? '<-' S Choice
    .Definition:
                .seq([
                    .call(.Identifier),
                    .call(._S),
                    .opt(
                        .seq([
                            .lit("{"),
                            .call(._S),
                            .call(.Options),
                            .call(._S),
                            .lit("}"),
                            .call(._S),
                            ])
                        ),
                    .lit("<-"),
                    .call(._S),
                    .call(.Choice),
                    ]),
    // Choice      { } <- Sequence ('/' S Sequence)*
    .Choice:
                .seq([
                    .call(.Sequence),
                    .rep(
                        .seq([
                            .lit("/"),
                            .call(._S),
                            .call(.Sequence),
                            ])
                        )
                    ]),
    // Sequence    { } <- Predicate+
    .Sequence:
                .rep1(.call(.Predicate)),
    // Predicate   { } <- (PredOp S)? Repeat
    .Predicate:
                .seq([
                    .opt(
                        .seq([
                            .call(.PredOp),
                            .call(._S),
                            ])
                        ),
                    .call(.Repeat)
                    ]),
    // Repeat      { } <- Primary (RepOp S)?
    .Repeat:
                .seq([
                    .call(.Primary),
                    .opt(
                        .seq([
                            .call(.RepOp),
                            .call(._S),
                            ])
                        )
                    ]),
    // Primary     { } <- Identifier S ![{<]
    //                  / '(' S Choice ')' S
    //                  / Literal S
    //                  / CharClass S
    //                  / Dot S
    .Primary:
                .alt([
                    .seq([
                        .call(.Identifier),
                        .call(._S),
                        .not(.chrs("{<"))
                        ]),
                    .seq([
                        .lit("("),
                        .call(._S),
                        .call(.Choice),
                        .lit(")"),
                        .call(._S),
                        ]),
                    .seq([
                        .call(.Literal),
                        .call(._S),
                        ]),
                    .seq([
                        .call(.CharClass),
                        .call(._S),
                        ]),
                    .seq([
                        .call(.Dot),
                        .call(._S),
                        ]),
                    ]),

    // # Lexical syntax
    
    // Options     { } <- [A-Za-z]*
    .Options:
                .rep(
                    .alt([.range("A","Z"), .range("a","z")]),
                    ),
    // Identifier  {L} <- [a-zA-Z_][a-zA-Z_0-9]*
    .Identifier:
                .seq([
                    .alt([.range("A","Z"), .range("a","z"), .lit("_")]),
                    .rep(
                        .alt([.range("A","Z"), .range("a","z"), .lit("_"), .range("0","9")])
                        )
                    ]),
    // Literal     {S} <- ['] (!['] Char)* [']
    //                  / ["] (!["] Char)* ["]
    .Literal:
                .alt([
                    .seq([
                        .lit("'"),
                        .rep(
                            .seq([
                                .not(.lit("'")),
                                .call(.Char)
                                ])
                            ),
                        .lit("'"),
                        ]),
                    .seq([
                        .lit("\""),
                        .rep(
                            .seq([
                                .not(.lit("\"")),
                                .call(.Char)
                                ])
                            ),
                        .lit("\""),
                        ])
                    ]),
    // CharClass   {S} <- '[' (!']' CharRange)+ ']'
    .CharClass:
                .seq([
                    .lit("["),
                    .rep1(
                        .seq([
                            .not(.lit("]")),
                            .call(.CharRange)
                        ])
                    ),
                    .lit("]"),
                    ]),
    // CharRange   { } <- Char '-' !']' Char / Char
    .CharRange:
                .alt([
                    .seq([
                        .call(.Char),
                        .lit("-"),
                        .not(.lit("]")),
                        .call(.Char),
                    ]),
                    .call(.Char),
                    ]),
    // Char        { } <- EscChar / OctChar / PlainChar
    .Char:
                .alt([
                    .call(.EscChar),
                    .call(.OctChar),
                    .call(.PlainChar),
                    ]),
    // EscChar     {L} <- '\\' [nrt'"\[\]\\]
    .EscChar:
                .seq([
                    .lit("\\"),
                    .chrs("nrt'\"[]\\"),
                   ]),
    // OctChar     {L} <- '\\' [0-3][0-7][0-7]
    //                  / '\\' [0-7][0-7]?
    .OctChar:
                .alt([
                    .seq([
                        .lit("\\"),
                        .range("0","3"),
                        .range("0","7"),
                        .range("0","7"),
                       ]),
                    .seq([
                        .lit("\\"),
                        .range("0","7"),
                        .opt(.range("0","7")),
                       ]),
                    ]),
    // PlainChar   {L} <- !'\\' .
    .PlainChar:
                .seq([
                    .not(.lit("\\")),
                    .any(1)
                    ]),
    // PredOp      {L} <- [&!]
    .PredOp:
                .chrs("&!"),
    // RepOp       {L} <- [*+?]
    .RepOp:
                .chrs("*+?"),
    // Dot         {L} <- '.'
    .Dot:
                .lit("."),
    // S           {I} <- ([ \t\r\n]+ / '#' (![\r\n] .)* [\r\n]? )*
    ._S:
                .rep(
                    .alt([
                        .rep1(
                            .chrs(" \t\n\r") // order matters, String considers \r\n a single character!
                            ),
                        .seq([
                            .lit("#"),
                            .rep(
                                .seq([
                                    .not(
                                        .chrs("\n\r")
                                    ),
                                    .any(1)
                                ])
                            ),
                            .opt(
                                .chrs("\n\r")
                            )
                        ])
                    ])
                )
]
