// generated 2026-10-13T10:17:13Z
enum chpegMachineSymbol: Int, CaseIterable, Sendable {
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
        S
}
let chpegMachine = PEMachine<chpegMachineSymbol>(
    program: [
    // Grammar:
       /*0*/.call(19), // S
       /*1*/.call(1), // Definition
       /*2*/.alt(5),
       /*3*/.call(1), // Definition
       /*4*/.rep(3),
       /*5*/.alt(8),
       /*6*/.any1,
       /*7*/.fail2,
       /*8*/.ret,
    // Definition:
       /*9*/.call(8), // Identifier
       /*10*/.call(19), // S
       /*11*/.alt(19),
       /*12*/.chr(123),
       /*13*/.call(19), // S
       /*14*/.call(7), // Options
       /*15*/.call(19), // S
       /*16*/.chr(125),
       /*17*/.call(19), // S
       /*18*/.commit(19),
       /*19*/.lit(60, "-".utf16),
       /*20*/.call(19), // S
       /*21*/.call(2), // Choice
       /*22*/.ret,
    // Choice:
       /*23*/.call(3), // Sequence
       /*24*/.alt(29),
       /*25*/.chr(47),
       /*26*/.call(19), // S
       /*27*/.call(3), // Sequence
       /*28*/.rep(25),
       /*29*/.ret,
    // Sequence:
       /*30*/.call(4), // Predicate
       /*31*/.alt(34),
       /*32*/.call(4), // Predicate
       /*33*/.rep(32),
       /*34*/.ret,
    // Predicate:
       /*35*/.alt(39),
       /*36*/.call(16), // PredOp
       /*37*/.call(19), // S
       /*38*/.commit(39),
       /*39*/.call(5), // Repeat
       /*40*/.ret,
    // Repeat:
       /*41*/.call(6), // Primary
       /*42*/.alt(46),
       /*43*/.call(17), // RepOp
       /*44*/.call(19), // S
       /*45*/.commit(46),
       /*46*/.ret,
    // Primary:
       /*47*/.alt(54),
       /*48*/.call(8), // Identifier
       /*49*/.call(19), // S
       /*50*/.alt(53),
       /*51*/.chrset(BitSet(words: [0x1000000000000000, 0x800000000000000])),
       /*52*/.fail2,
       /*53*/.commit(71),
       /*54*/.alt(61),
       /*55*/.chr(40),
       /*56*/.call(19), // S
       /*57*/.call(2), // Choice
       /*58*/.chr(41),
       /*59*/.call(19), // S
       /*60*/.commit(71),
       /*61*/.alt(65),
       /*62*/.call(9), // Literal
       /*63*/.call(19), // S
       /*64*/.commit(71),
       /*65*/.alt(69),
       /*66*/.call(10), // CharClass
       /*67*/.call(19), // S
       /*68*/.commit(71),
       /*69*/.call(18), // Dot
       /*70*/.call(19), // S
       /*71*/.ret,
    // Options:
       /*72*/.spanset(BitSet(words: [0x0, 0x7FFFFFE07FFFFFE])),
       /*73*/.ret,
    // Identifier:
       /*74*/.chrset(BitSet(words: [0x0, 0x7FFFFFE87FFFFFE])),
       /*75*/.spanset(BitSet(words: [0x3FF000000000000, 0x7FFFFFE87FFFFFE])),
       /*76*/.ret,
    // Literal:
       /*77*/.alt(87),
       /*78*/.range(39, 39),
       /*79*/.alt(85),
       /*80*/.alt(83),
       /*81*/.range(39, 39),
       /*82*/.fail2,
       /*83*/.call(12), // Char
       /*84*/.rep(80),
       /*85*/.range(39, 39),
       /*86*/.commit(95),
       /*87*/.range(34, 34),
       /*88*/.alt(94),
       /*89*/.alt(92),
       /*90*/.range(34, 34),
       /*91*/.fail2,
       /*92*/.call(12), // Char
       /*93*/.rep(89),
       /*94*/.range(34, 34),
       /*95*/.ret,
    // CharClass:
       /*96*/.chr(91),
       /*97*/.alt(100),
       /*98*/.chr(93),
       /*99*/.fail2,
       /*100*/.call(11), // CharRange
       /*101*/.alt(107),
       /*102*/.alt(105),
       /*103*/.chr(93),
       /*104*/.fail2,
       /*105*/.call(11), // CharRange
       /*106*/.rep(102),
       /*107*/.chr(93),
       /*108*/.ret,
    // CharRange:
       /*109*/.alt(117),
       /*110*/.call(12), // Char
       /*111*/.chr(45),
       /*112*/.alt(115),
       /*113*/.chr(93),
       /*114*/.fail2,
       /*115*/.call(12), // Char
       /*116*/.commit(118),
       /*117*/.call(12), // Char
       /*118*/.ret,
    // Char:
       /*119*/.alt(122),
       /*120*/.call(13), // EscChar
       /*121*/.commit(126),
       /*122*/.alt(125),
       /*123*/.call(14), // OctChar
       /*124*/.commit(126),
       /*125*/.call(15), // PlainChar
       /*126*/.ret,
    // EscChar:
       /*127*/.chr(92),
       /*128*/.chrset(BitSet(words: [0x8400000000, 0x14400038000000])),
       /*129*/.ret,
    // OctChar:
       /*130*/.alt(136),
       /*131*/.chr(92),
       /*132*/.range(48, 51),
       /*133*/.range(48, 55),
       /*134*/.range(48, 55),
       /*135*/.commit(141),
       /*136*/.chr(92),
       /*137*/.range(48, 55),
       /*138*/.alt(141),
       /*139*/.range(48, 55),
       /*140*/.commit(141),
       /*141*/.ret,
    // PlainChar:
       /*142*/.alt(145),
       /*143*/.chr(92),
       /*144*/.fail2,
       /*145*/.any1,
       /*146*/.ret,
    // PredOp:
       /*147*/.chrset1(283467841536),
       /*148*/.ret,
    // RepOp:
       /*149*/.chrset1(9223385230994309120),
       /*150*/.ret,
    // Dot:
       /*151*/.chr(46),
       /*152*/.ret,
    // S:
       /*153*/.alt(169),
       /*154*/.alt(158),
       /*155*/.chrset1(4294977024),
       /*156*/.spanset1(4294977024),
       /*157*/.commit(168),
       /*158*/.chr(35),
       /*159*/.alt(165),
       /*160*/.alt(163),
       /*161*/.chrset1(9216),
       /*162*/.fail2,
       /*163*/.any1,
       /*164*/.rep(160),
       /*165*/.alt(168),
       /*166*/.chrset1(9216),
       /*167*/.commit(168),
       /*168*/.rep(154),
       /*169*/.ret,
        ],
    start: [
        /*Grammar*/ 0,
        /*Definition*/ 9,
        /*Choice*/ 23,
        /*Sequence*/ 30,
        /*Predicate*/ 35,
        /*Repeat*/ 41,
        /*Primary*/ 47,
        /*Options*/ 72,
        /*Identifier*/ 74,
        /*Literal*/ 77,
        /*CharClass*/ 96,
        /*CharRange*/ 109,
        /*Char*/ 119,
        /*EscChar*/ 127,
        /*OctChar*/ 130,
        /*PlainChar*/ 142,
        /*PredOp*/ 147,
        /*RepOp*/ 149,
        /*Dot*/ 151,
        /*S*/ 153,
        ],
    ignore: [
        /*Grammar*/ false,
        /*Definition*/ false,
        /*Choice*/ false,
        /*Sequence*/ false,
        /*Predicate*/ false,
        /*Repeat*/ false,
        /*Primary*/ false,
        /*Options*/ false,
        /*Identifier*/ false,
        /*Literal*/ false,
        /*CharClass*/ false,
        /*CharRange*/ false,
        /*Char*/ false,
        /*EscChar*/ false,
        /*OctChar*/ false,
        /*PlainChar*/ false,
        /*PredOp*/ false,
        /*RepOp*/ false,
        /*Dot*/ false,
        /*S*/ true,
       ]
)
