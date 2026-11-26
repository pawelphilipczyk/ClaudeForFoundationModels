// SPDX-License-Identifier: Apache-2.0

import Foundation

extension JSONValue {
  /// The key a `GenerationSchema` keeps its properties' declaration order in.
  package static let orderKey = "x-order"

  /// Rewrites JSON so that every schema object's `properties` come in the
  /// order its `x-order` names, and drops `x-order` (the API rejects it).
  /// Every other object keeps its keys sorted, so the bytes stay deterministic.
  ///
  /// `JSONEncoder` cannot do this: without `.sortedKeys` it writes keys in
  /// hash order, which changes on every launch.
  package static func orderedData(from data: Data) throws -> Data {
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    var output = ""
    try value.write(into: &output)
    return Data(output.utf8)
  }

  private func write(into output: inout String) throws {
    switch self {
    case .null: output += "null"
    case .bool(let value): output += value ? "true" : "false"
    case .number(let value): try Self.write(number: value, into: &output)
    case .string(let value):
      output += String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    case .array(let values):
      output += "["
      for (position, value) in values.enumerated() {
        if position > 0 { output += "," }
        try value.write(into: &output)
      }
      output += "]"
    case .object(let fields):
      let order = Self.propertyOrder(of: fields)
      output += "{"
      var first = true
      for key in fields.keys.sorted() where !(key == Self.orderKey && order != nil) {
        if !first { output += "," }
        first = false
        output += String(decoding: try JSONEncoder().encode(key), as: UTF8.self) + ":"
        if key == "properties", let order, case .object(let properties)? = fields[key] {
          try Self.write(properties, in: order, into: &output)
        } else {
          try fields[key]?.write(into: &output)
        }
      }
      output += "}"
    }
  }

  /// The declared order of a schema object's properties: only where both
  /// `properties` and an `x-order` list of names are present.
  private static func propertyOrder(of fields: [String: JSONValue]) -> [String]? {
    guard case .object? = fields["properties"], case .array(let names)? = fields[orderKey] else {
      return nil
    }
    let order = names.compactMap { name -> String? in
      if case .string(let text) = name { text } else { nil }
    }
    return order.count == names.count ? order : nil
  }

  /// The named properties first, in `order`; any the order does not name
  /// after them, sorted.
  private static func write(
    _ properties: [String: JSONValue],
    in order: [String],
    into output: inout String
  ) throws {
    let named = order.filter { properties[$0] != nil }
    let rest = properties.keys.filter { !named.contains($0) }.sorted()
    output += "{"
    for (position, key) in (named + rest).enumerated() {
      if position > 0 { output += "," }
      output += String(decoding: try JSONEncoder().encode(key), as: UTF8.self) + ":"
      try properties[key]?.write(into: &output)
    }
    output += "}"
  }

  /// Whole numbers as integers (`max_tokens: 1024`, not `1024.0`); others as
  /// `JSONEncoder` writes them.
  private static func write(number: Double, into output: inout String) throws {
    if number.rounded() == number, abs(number) < 1e15 {
      output += String(Int64(number))
    } else {
      output += String(decoding: try JSONEncoder().encode(number), as: UTF8.self)
    }
  }
}
