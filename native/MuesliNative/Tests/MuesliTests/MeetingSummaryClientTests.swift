import Testing
import Foundation
import MuesliCore
@testable import MuesliNativeApp

@Suite("MeetingSummaryClient")
struct MeetingSummaryClientTests {

    @Test("summarize returns raw transcript fallback when no API key")
    func fallbackWithoutKey() async {
        var config = AppConfig()
        config.openAIAPIKey = ""
        config.meetingSummaryBackend = "openai"

        let result = await MeetingSummaryClient.summarize(
            transcript: "Hello world",
            meetingTitle: "Test",
            config: config
        )

        #expect(result.contains("# Test"))
        #expect(result.contains("## Raw Transcript"))
        #expect(result.contains("Hello world"))
    }

    @Test("summarize routes to OpenRouter when configured")
    func routesToOpenRouter() async {
        var config = AppConfig()
        config.openRouterAPIKey = ""
        config.meetingSummaryBackend = "openrouter"

        let result = await MeetingSummaryClient.summarize(
            transcript: "Test transcript",
            meetingTitle: "My Meeting",
            config: config
        )

        // No key → falls back to raw transcript
        #expect(result.contains("# My Meeting"))
        #expect(result.contains("## Raw Transcript"))
    }

    @Test("generateTitle returns nil without API key")
    func titleWithoutKey() async {
        var config = AppConfig()
        config.openAIAPIKey = ""
        config.meetingSummaryBackend = "openai"

        let title = await MeetingSummaryClient.generateTitle(
            transcript: "We discussed the quarterly review",
            config: config
        )

        #expect(title == nil)
    }

    @Test("generateTitle returns nil for OpenRouter without key")
    func titleOpenRouterWithoutKey() async {
        var config = AppConfig()
        config.openRouterAPIKey = ""
        config.meetingSummaryBackend = "openrouter"

        let title = await MeetingSummaryClient.generateTitle(
            transcript: "Sprint planning discussion",
            config: config
        )

        #expect(title == nil)
    }

    @Test("summarize defaults to openai backend when empty")
    func defaultsToOpenAI() async {
        var config = AppConfig()
        config.meetingSummaryBackend = ""
        config.openAIAPIKey = ""

        let result = await MeetingSummaryClient.summarize(
            transcript: "Test", meetingTitle: "Title", config: config
        )

        // Should hit OpenAI path, fail (no key), return fallback
        #expect(result.contains("## Raw Transcript"))
    }
}
