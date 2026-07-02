//
//  RecommendationMetadataRankerTests.swift
//  ApexTests
//

import Foundation
@testable import Apex
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct RecommendationMetadataRankerTests {
    @Test func `normalizedGenres splits provider strings`() {
        let genres = RecommendationMetadataRanker.normalizedGenres("Action, Drama | Sci-Fi")
        #expect(genres.contains("action"))
        #expect(genres.contains("drama"))
        #expect(genres.contains("sci-fi"))
    }

    @Test func `ranks by genre overlap without embeddings`() async throws {
        let container = try makeTestContainer()
        let liked = Movie(id: "liked", streamId: 1, name: "Liked")
        liked.genre = "Action, Drama"
        liked.isFavorite = true

        let similar = Movie(id: "similar", streamId: 2, name: "Similar")
        similar.genre = "Action, Thriller"

        let different = Movie(id: "different", streamId: 3, name: "Different")
        different.genre = "Comedy"

        container.mainContext.insert(liked)
        container.mainContext.insert(similar)
        container.mainContext.insert(different)
        try container.mainContext.save()

        let context = ModelContext(container)
        let profile = try #require(RecommendationMetadataRanker.buildProfile(
            context: context,
            signalLimit: 50,
            favoriteWeight: 1,
            watchedWeight: 0.6,
            upvote: 1,
            downvote: -1
        ))
        let ranked = RecommendationMetadataRanker.rankCandidates(
            limit: 5,
            context: context,
            profile: profile,
            pageSize: 100,
            downvote: -1
        )
        #expect(ranked.first?.id == "similar")
    }
}

@MainActor
@Suite(.serialized)
struct RecommendationEngineMetadataFallbackTests {
    private func isolatedStore() -> RecommendationCacheStore {
        RecommendationCacheStore(defaults: UserDefaults(suiteName: "rec-meta-test-\(UUID().uuidString)")!)
    }

    @Test func `uses metadata fallback when embeddings are absent`() async throws {
        let container = try makeTestContainer()
        let liked = Movie(id: "liked", streamId: 1, name: "Liked")
        liked.genre = "Action"
        liked.isFavorite = true

        let candidate = Movie(id: "candidate", streamId: 2, name: "Candidate")
        candidate.genre = "Action"

        container.mainContext.insert(liked)
        container.mainContext.insert(candidate)
        try container.mainContext.save()

        let engine = RecommendationEngine(
            modelContainer: container,
            cacheStore: isolatedStore(),
            recalculationInterval: 0
        )
        let ids = await engine.recommendations().map(\.id)
        #expect(ids.contains("candidate"))
    }
}
