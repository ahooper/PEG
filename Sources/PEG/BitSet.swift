//
//  BitSet.swift
//  pgen
//
//  Created by Andy Hooper on 2026-01-20.
//
//  https://github.com/lemire/SwiftBitset/blob/master/Sources/Bitset/Bitset.swift

public struct BitSet: Codable, Equatable, CustomStringConvertible, Sendable {
    public typealias Word =  UInt64
    let words: [Word]
    
    public init(words: [Word]) {
        self.words = words
    }

    public init(_ list: [UInt32]) {
        words = BitSet.build(list)
    }

    public init(_ list: [ClosedRange<UInt32>]) {
        words = BitSet.build(list.flatMap({ r in (r.lowerBound ... r.upperBound).makeIterator() }))
    }

    private static func build(_ list: [UInt32])->[Word] {
        let max = list.max()!,
            nWords = (Int(max) + Word.bitWidth - 1) / Word.bitWidth
        var words = [Word](repeating: .zero, count: nWords)
        for element in list {
            words[Int(element) / Word.bitWidth] |= 1 << (Int(element) % Word.bitWidth)
        }
        //print(#function, words.map({ w in String(String(w, radix: 2).reversed()) }))
        return words
    }
    
    public func contains(_ value: UInt32)->Bool {
        value < words.count * Word.bitWidth &&
            (words[Int(value) / Word.bitWidth] & (1 << (Int(value) % Word.bitWidth))) != 0
    }
    
    public static func wordContains(_ word: Word, _ value: UInt32)->Bool {
        value < Word.bitWidth &&
            (word & (1 << Int(value))) != 0
    }
    
    public var description: String { "BitSet(words: ["+words.map({ w in
                                    "0x"+String(w, radix: 16, uppercase: true)
                                }).joined(separator: ", ")+"])" }

}

//TODO: could special case small sets, of 1 or 2 words, for compiled code
