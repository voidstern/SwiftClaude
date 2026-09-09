extension ToolInput {

  public static func schema<T: ToolInput.SchemaCodable & FloatingPoint & Codable & Sendable>(
    representing _: T.Type = T.self
  ) -> some Schema<T> {
    NumberSchema()
  }

}

extension Float: ToolInput.SchemaCodable {}
#if !targetEnvironment(macCatalyst)
extension Float16: ToolInput.SchemaCodable {}
#endif
extension Double: ToolInput.SchemaCodable {}

// MARK: - Implementation Details

extension ToolInput.SchemaCodable where Self: FloatingPoint & Codable & Sendable {

  public static var toolInputSchema: some ToolInput.Schema<Self> {
    ToolInput.schema()
  }

}

private struct NumberSchema<Value: Codable & Sendable>: LeafSchema {

  let type = "number"

}
