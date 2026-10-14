public import ClaudeClient

extension ClaudeClient.MessagesEndpoint.Response.Event.ContentBlockDelta.Delta {

  public var asTextDelta: TextDelta {
    get throws {
      switch self {
      case .textDelta(let delta):
        return delta
      case .inputJsonDelta:
        throw Error.InvalidDelta(expected: .text, observed: .inputJson)
      case .thinkingDelta:
        throw Error.InvalidDelta(expected: .text, observed: .thinking)
      case .signatureDelta:
        throw Error.InvalidDelta(expected: .text, observed: .signature)
      }
    }
  }

  public var asInputJsonDelta: InputJsonDelta {
    get throws {
      switch self {
      case .textDelta:
        throw Error.InvalidDelta(expected: .inputJson, observed: .text)
      case .inputJsonDelta(let delta):
        return delta
      case .thinkingDelta:
        throw Error.InvalidDelta(expected: .inputJson, observed: .thinking)
      case .signatureDelta:
        throw Error.InvalidDelta(expected: .inputJson, observed: .signature)
      }
    }
  }

  private enum Error {
    struct InvalidDelta: Swift.Error {
      enum Kind {
        case text, inputJson, thinking, signature
      }
      let expected: Kind
      let observed: Kind
    }
  }

}

extension ClaudeClient.MessagesEndpoint.Response.Event.ContentBlockStart.ContentBlock {

  public var text: Text {
    get throws {
      switch self {
      case .text(let text):
        return text
      case .toolUse:
        throw Error.InvalidDelta(expected: .text, observed: .inputJson)
      case .thinking, .redactedThinking:
        throw Error.InvalidDelta(expected: .text, observed: .thinking)
      }
    }
  }

  public var toolUse: ToolUse {
    get throws {
      switch self {
      case .text:
        throw Error.InvalidDelta(expected: .inputJson, observed: .text)
      case .toolUse(let delta):
        return delta
      case .thinking, .redactedThinking:
        throw Error.InvalidDelta(expected: .inputJson, observed: .thinking)
      }
    }
  }

  private enum Error {
    struct InvalidStart: Swift.Error {
      enum Kind {
        case text, inputJson
      }
      let expected: Kind
      let observed: Kind
    }
    struct InvalidDelta: Swift.Error {
      enum Kind {
        case text, inputJson, thinking
      }
      let expected: Kind
      let observed: Kind
    }
  }

}
