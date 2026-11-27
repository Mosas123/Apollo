//
//  SearchSuggestionsTests.swift
//  ApolloTubeTests
//
//  Created by 686udjie on 17/10/2026.
//

import Foundation
import Testing

@testable import ApolloTube

@Suite("Search suggestions")
struct SearchSuggestionsTests {
    @Test("Plain JSON array parses to suggestions")
    func plainArray() {
        let data = Data(#"["cat",[["cats",0],["cat videos",0]]]"#.utf8)
        #expect(SearchSuggestions.parse(data: data) == ["cats", "cat videos"])
    }

    @Test("Firefox autocomplete strings parse")
    func firefoxArray() {
        let data = Data(#"["bad",["bad bunny","bad romance"]]"#.utf8)
        #expect(SearchSuggestions.parse(data: data) == ["bad bunny", "bad romance"])
    }

    @Test("JSONP wrapper parses")
    func jsonp() {
        let data = Data(#"window.google.ac.h(["cat",[["cats",0],[123,0]]])"#.utf8)
        #expect(SearchSuggestions.parse(data: data) == ["cats"])
    }

    @Test("Malformed payloads yield no suggestions")
    func malformed() {
        #expect(SearchSuggestions.parse(data: Data("not json".utf8)).isEmpty)
        #expect(SearchSuggestions.parse(data: Data(#"["only-query"]"#.utf8)).isEmpty)
    }
}
