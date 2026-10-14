import Foundation
import Testing
import ClaudeClient

@testable import ClaudeAPI

@Suite
@MainActor
private struct ThinkingBlocksTests {

  @Test(arguments: ["", "Private reasoning. "])
  func thinkingIsExcludedFromTextAndPreservedForReplay(_ thinking: String) async throws {
    let events = thinkingEvents(thinking) + [
      #"{"type":"content_block_start","index":1,"content_block":{"type":"redacted_thinking","data":"opaque-data"}}"#,
      #"{"type":"content_block_stop","index":1}"#
    ] + textEvents(index: 2)
    let message = client(events).nextMessage(in: Conversation(messages: [.user("Summarize.")]))
    var streamedText = ""
    for try await fragment in message.textSegments { streamedText += fragment }
    #expect(streamedText == "Article summary.")
    #expect(try await message.text() == "Article summary.")
    #expect(message.currentContentBlocks.count == 1)
    let metadata = try await message.metadata()
    #expect(metadata.stopReason == .endTurn)
    #expect(metadata.usage.inputTokens == 12)
    #expect(metadata.usage.outputTokens == 34)
    let replay = try encodedMessages(Conversation(messages: [.assistant(message)]))
    let blocks = try #require(replay.first?["content"] as? [[String: Any]])
    #expect(blocks.map { $0["type"] as? String } == ["thinking", "redacted_thinking", "text"])
    #expect(blocks[0]["thinking"] as? String == thinking + thinking)
    #expect(blocks[0]["signature"] as? String == "signature-prefix-part-1-part-2")
    #expect(blocks[1]["data"] as? String == "opaque-data")
    #expect(blocks[2]["text"] as? String == "Article summary.")
  }

  @Test
  func textOnlyStillWorks() async throws {
    let message = client(textEvents(index: 0)).nextMessage(in: Conversation(messages: [.user("Summarize.")]))
    #expect(try await message.text() == "Article summary.")
    let replay = try encodedMessages(Conversation(messages: [.assistant(message)]))
    #expect(replay.first?["content"] as? String == "Article summary.")
  }

  @Test
  func thinkingBeforeToolUsePreservesBlockOrderAndToolResult() async throws {
    let events = thinkingEvents("") + [
      #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_1","name":"EchoTool","input":{}}}"#,
      #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"value\":\"echo\"}"}}"#,
      #"{"type":"content_block_stop","index":1}"#
    ]
    let message = client(events, stopReason: "tool_use").nextMessage(in: ToolConversation(messages: [.user("Echo.")]), tools: [EchoTool()], invokeTools: .whenStreamingSuccessful)
    try await message.toolInvocationComplete()
    #expect(message.currentError == nil)
    #expect(message.currentContentBlocks.count == 1)
    let replay = try encodedMessages(ToolConversation(messages: [.assistant(message)]))
    let blocks = try #require(replay[0]["content"] as? [[String: Any]])
    #expect(blocks.map { $0["type"] as? String } == ["thinking", "tool_use"])
    #expect((blocks[1]["input"] as? [String: String])?["value"] == "echo")
    let results = try #require(replay[1]["content"] as? [[String: Any]])
    #expect(results[0]["tool_use_id"] as? String == "tool_1")
    #expect(results[0]["content"] as? String == "echo")
  }

  @Test(arguments: [
    #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"wrong delta"}}"#,
    #"{"type":"content_block_delta","index":1,"delta":{"type":"signature_delta","signature":"wrong index"}}"#,
    #"{"type":"content_block_start","index":1,"content_block":{"type":"unknown_block"}}"#
  ])
  func invalidThinkingStreamsStillFail(_ invalidEvent: String) async throws {
    let message = client([thinkingEvents("")[0], invalidEvent]).nextMessage(in: Conversation(messages: [.user("Summarize.")]))
    await #expect(throws: (any Error).self) { try await message.text() }
    #expect(message.currentError != nil)
    #expect(throws: (any Error).self) { try encodedMessages(Conversation(messages: [.assistant(message)])) }
  }

  @Test
  func unfinishedThinkingStillFails() async throws {
    let message = client([thinkingEvents("")[0]]).nextMessage(in: Conversation(messages: [.user("Summarize.")]))
    await #expect(throws: (any Error).self) { try await message.text() }
  }

  @Test
  func unsignedThinkingCannotBeReplayed() async throws {
    let events = [
      #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
      #"{"type":"content_block_stop","index":0}"#
    ] + textEvents(index: 1)
    let message = client(events).nextMessage(in: Conversation(messages: [.user("Summarize.")]))
    _ = try await message.text()
    #expect(throws: (any Error).self) { try encodedMessages(Conversation(messages: [.assistant(message)])) }
  }

  private func thinkingEvents(_ text: String) -> [String] {
    [
      #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"\#(text)","signature":"signature-prefix"}}"#,
      #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\#(text)"}}"#,
      #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"-part-1"}}"#,
      #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"-part-2"}}"#,
      #"{"type":"content_block_stop","index":0}"#
    ]
  }

  private func textEvents(index: Int) -> [String] {
    [
      #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"text","text":"Article "}}"#,
      #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"text_delta","text":"summary."}}"#,
      #"{"type":"content_block_stop","index":\#(index)}"#
    ]
  }

  private func client(_ contentEvents: [String], stopReason: String = "end_turn") -> Claude {
    let events = [
      #"{"type":"message_start","message":{"id":"msg_fixture","model":"claude-haiku-5-5","usage":{"input_tokens":12,"output_tokens":0}}}"#,
      #"{"type":"ping"}"#
    ] + contentEvents + [
      #"{"type":"message_delta","delta":{"stop_reason":"\#(stopReason)","stop_sequence":null},"usage":{"output_tokens":34}}"#,
      #"{"type":"message_stop"}"#
    ]
    return Claude(client: ClaudeClient(backend: .production, authenticator: FixtureAuthenticator(), httpTransport: FixtureTransport(events: events)))
  }

  private func encodedMessages<C: Claude.Conversation>(_ conversation: C) throws -> [[String: Any]] {
    let messages = try conversation.messagesRequestMessages(for: .default, imagePreprocessingMode: .recommended())
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return try #require(JSONSerialization.jsonObject(with: encoder.encode(messages)) as? [[String: Any]])
  }
}

private struct Conversation: Claude.Conversation {
  var messages: [Message]
}

private struct ToolConversation: Claude.Conversation {
  typealias ToolOutput = String
  var messages: [Message]
}

@Tool
private struct EchoTool {
  func invoke(value: String) -> String { value }
}

private struct FixtureAuthenticator: Claude.Authenticator {
  let apiKey: Claude.APIKey? = .init("fixture-key")
}

private struct FixtureTransport: ClaudeClient.HTTPTransport {
  let events: [String]

  func send(_ request: Request, isolation: isolated any Actor) async throws -> sending Response {
    let body = AsyncThrowingStream<Data, Error> { continuation in
      for event in events {
        let object = try! JSONSerialization.jsonObject(with: Data(event.utf8)) as! [String: Any]
        continuation.yield(Data("event: \(object["type"]!)\ndata: \(event)\n\n".utf8))
      }
      continuation.finish()
    }
    return Response(http: .init(status: .ok), body: body, holdOnto: ())
  }
}
