import Foundation

/// A decoder that decodes instances of `Decodable` types from XML data using XMLParser.
public final class XMLStreamDecoder {
    // MARK: - Configuration

    /// The strategy to use for decoding keys. Defaults to `.useDefaultKeys`.
    public let keyDecodingStrategy: KeyDecodingStrategy

    public init(_ keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys) {
        self.keyDecodingStrategy = keyDecodingStrategy
    }

    // MARK: - Decoding

    /// Decodes an instance of the specified type from XML data.
    ///
    /// - Parameters:
    ///   - type: The type of the value to decode.
    ///   - data: The XML data to decode.
    /// - Returns: A value of the specified type.
    /// - Throws: An error if decoding fails.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let parser = XMLParser(data: data)
        let delegate = CodableXMLParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "The given data was not valid XML.",
                underlyingError: parser.parserError
            ))
        }

        guard let rootNode = delegate.rootNode else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "XML has no root element."
            ))
        }

        let decoder = _XMLStreamDecoder(
            node: rootNode,
            codingPath: [],
            keyDecodingStrategy: keyDecodingStrategy,
        )

        let decoded = try T(from: decoder)
        return decoded
    }

    // MARK: - Key Decoding Strategy
    public enum KeyDecodingStrategy {
        case useDefaultKeys
        case convertFromKebabCase
    }
}

// MARK: - XML Node

/// A lightweight representation of an XML element.
private class XMLNode: CustomStringConvertible {
    var name: String
    var attributes: [String: String]
    var stringValue: String?
    var children: [XMLNode]

    init(name: String, attributes: [String: String] = [:], stringValue: String? = nil, children: [XMLNode] = []) {
        self.name = name
        self.attributes = attributes
        self.stringValue = stringValue
        self.children = children
    }

    /// Finds all child nodes with the given name.
    func children(named name: String) -> [XMLNode] {
        return children.filter { $0.name == name }
    }

    /// Returns the attribute with the given name, if any.
    func attribute(named name: String) -> String? {
        return attributes[name]
    }

    var description: String {
        var description = "Name: \(name). Attributes: \(attributes). String value: \(stringValue ?? "")\n"
        for child in children {
            description.append("\n\t\(child.description)".replacingOccurrences(of: "\n", with: "\n\t"))
        }

        return description
    }
}

// MARK: - XML Parser Delegate

private class CodableXMLParserDelegate: NSObject, XMLParserDelegate {
    var rootNode: XMLNode?
    private var currentNode: XMLNode?
    private var nodeStack: [XMLNode] = []
    private var textBuffer: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XMLNode(name: elementName, attributes: attributeDict)

        if currentNode == nil {
            // This is the root node
            rootNode = node
        } else {
            // Add as child to current node
            currentNode?.children.append(node)
        }

        // Push to stack and update current node
        nodeStack.append(node)
        currentNode = node
        textBuffer = nil
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // Set string value from accumulated text
        if let text = textBuffer?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            currentNode?.stringValue = text
        }

        // Pop from stack
        nodeStack.removeLast()
        currentNode = nodeStack.last
        textBuffer = nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Accumulate text content
        if textBuffer == nil {
            textBuffer = string
        } else {
            textBuffer! += string
        }
    }
}

// MARK: - XML Stream Decoder Implementation

private class _XMLStreamDecoder: Decoder {
    var userInfo: [CodingUserInfoKey: Any]

    // The current node being decoded
    let node: XMLNode

    // The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]

    // Decoding configuration
    let keyDecodingStrategy: XMLStreamDecoder.KeyDecodingStrategy

    init(
        node: XMLNode,
        codingPath: [CodingKey],
        keyDecodingStrategy: XMLStreamDecoder.KeyDecodingStrategy,
    ) {
        self.node = node
        self.codingPath = codingPath
        self.keyDecodingStrategy = keyDecodingStrategy
        self.userInfo = [:]
    }

    // MARK: - Decoder Methods

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        let container = XMLKeyedDecodingContainer<Key>(
            node: node,
            codingPath: codingPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return XMLUnkeyedDecodingContainer(
            nodes: node.children,
            codingPath: codingPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return XMLSingleValueDecodingContainer(
            node: node,
            codingPath: codingPath,
        )
    }
}

// MARK: - Keyed Decoding Container

private struct XMLKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K

    // The node from which this container is decoding.
    let node: XMLNode

    // The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]

    // Decoding configuration
    let keyDecodingStrategy: XMLStreamDecoder.KeyDecodingStrategy

    // MARK: - KeyedDecodingContainerProtocol Methods

    var allKeys: [K] {
        // Combine attribute keys and child element names as potential coding keys
        var keys: [String] = Array(node.attributes.keys)
        for child in node.children where !keys.contains(child.name) {
            keys.append(child.name)
        }

        // Convert to coding keys
        return keys.compactMap {
            xmlKeyToCodingKey($0, ofType: K.self)
        }
    }

    func contains(_ key: K) -> Bool {
        // Check if we have an attribute with this key
        if let attrKey = codingKeyToXMLKey(key), node.attributes[attrKey] != nil {
            return true
        }

        // Check if we have a child element with this key
        if let elemKey = codingKeyToXMLKey(key), !node.children(named: elemKey).isEmpty {
            return true
        }

        return false
    }

    func decodeNil(forKey key: K) throws -> Bool {
        guard contains(key) else {
            return true
        }

        if let xmlKey = codingKeyToXMLKey(key) {
            // Check if it's an empty element or attribute
            if let attr = node.attribute(named: xmlKey) {
                return attr.isEmpty
            }

            let children = node.children(named: xmlKey)
            if !children.isEmpty {
                let child = children[0]
                return child.stringValue == nil && child.children.isEmpty && child.attributes.isEmpty
            }
        }

        return false
    }

    func decode(_ type: Bool.Type, forKey key: K) throws -> Bool {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: String.Type, forKey key: K) throws -> String {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: Double.Type, forKey key: K) throws -> Double {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: Float.Type, forKey key: K) throws -> Float {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: Int.Type, forKey key: K) throws -> Int {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: Int8.Type, forKey key: K) throws -> Int8 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: Int16.Type, forKey key: K) throws -> Int16 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: Int32.Type, forKey key: K) throws -> Int32 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: Int64.Type, forKey key: K) throws -> Int64 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: UInt.Type, forKey key: K) throws -> UInt {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: UInt8.Type, forKey key: K) throws -> UInt8 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 {
        return try decodePrimitive(type, forKey: key)
    }

    func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T: Decodable {
        let newPath = codingPath + [key]

        // Try to find the XML element or attribute
        guard let xmlKey = codingKeyToXMLKey(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        // First check for attributes
        if let attrValue = node.attribute(named: xmlKey) {
            let container = XMLSingleValueDecodingContainer(
                value: attrValue,
                codingPath: newPath,
            )

            return try container.decode(type)
        }

        // Then check for child elements
        let children = node.children(named: xmlKey)
        if !children.isEmpty {
            let childNode = children[0]
            let decoder = _XMLStreamDecoder(
                node: childNode,
                codingPath: newPath,
                keyDecodingStrategy: keyDecodingStrategy,
            )

            return try T(from: decoder)
        }

        throw DecodingError.keyNotFound(key, DecodingError.Context(
            codingPath: newPath,
            debugDescription: "No value associated with key \(key.stringValue)."
        ))
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        let newPath = codingPath + [key]

        guard let xmlKey = codingKeyToXMLKey(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        let children = node.children(named: xmlKey)
        guard !children.isEmpty else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        let childNode = children[0]
        let container = XMLKeyedDecodingContainer<NestedKey>(
            node: childNode,
            codingPath: newPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )

        return KeyedDecodingContainer(container)
    }

    func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        let newPath = codingPath + [key]

        guard let xmlKey = codingKeyToXMLKey(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        let children = node.children(named: xmlKey)
        guard !children.isEmpty else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        // In XML, an unkeyed container is represented by repeated elements with the same name
        return XMLUnkeyedDecodingContainer(
            nodes: children,
            codingPath: newPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )
    }

    func superDecoder() throws -> Decoder {
        return _XMLStreamDecoder(
            node: node,
            codingPath: codingPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )
    }

    func superDecoder(forKey key: K) throws -> Decoder {
        let newPath = codingPath + [key]

        guard let xmlKey = codingKeyToXMLKey(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        let children = node.children(named: xmlKey)
        guard !children.isEmpty else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        return _XMLStreamDecoder(
            node: children[0],
            codingPath: newPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )
    }

    // MARK: - Helper Methods

    private func decodePrimitive<T>(_ type: T.Type, forKey key: K) throws -> T where T: Decodable & LosslessStringConvertible {
        let newPath = codingPath + [key]

        guard let xmlKey = codingKeyToXMLKey(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        // First check for attributes
        if let attrValue = node.attribute(named: xmlKey) {
            guard let value = T(attrValue) else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(
                    codingPath: newPath,
                    debugDescription: "Could not convert attribute value \"\(attrValue)\" to type \(type)."
                ))
            }
            return value
        }

        // Then check for child elements
        let children = node.children(named: xmlKey)
        if !children.isEmpty {
            let childNode = children[0]
            guard let stringValue = childNode.stringValue else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(
                    codingPath: newPath,
                    debugDescription: "Expected \(type) value but found null instead."
                ))
            }

            guard let value = T(stringValue) else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(
                    codingPath: newPath,
                    debugDescription: "Could not convert element value \"\(stringValue)\" to type \(type)."
                ))
            }
            return value
        }

        // If we get here, the key wasn't found
        throw DecodingError.keyNotFound(key, DecodingError.Context(
            codingPath: newPath,
            debugDescription: "No value associated with key \(key.stringValue)."
        ))
    }

    private func nestedSingleValueContainer(forKey key: K) throws -> SingleValueDecodingContainer {
        let newPath = codingPath + [key]

        guard let xmlKey = codingKeyToXMLKey(key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: newPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }

        // First check for attributes
        if let attrValue = node.attribute(named: xmlKey) {
            return XMLSingleValueDecodingContainer(
                value: attrValue,
                codingPath: newPath,
            )
        }

        // Then check for child elements
        let children = node.children(named: xmlKey)
        if !children.isEmpty {
            let childNode = children[0]
            return XMLSingleValueDecodingContainer(
                node: childNode,
                codingPath: newPath,
            )
        }

        // If we get here, the key wasn't found
        throw DecodingError.keyNotFound(key, DecodingError.Context(
            codingPath: newPath,
            debugDescription: "No value associated with key \(key.stringValue)."
        ))
    }

    // Convert from CodingKey to XML key based on the strategy
    private func codingKeyToXMLKey(_ key: K) -> String? {
        switch keyDecodingStrategy {
        case .useDefaultKeys:
            return key.stringValue

        case .convertFromKebabCase:
            return kebabify(key.stringValue)
        }
    }

    // Convert from XML key to CodingKey based on the strategy
    private func xmlKeyToCodingKey<T: CodingKey>(_ key: String, ofType: T.Type) -> T? {
        let codingKey: String

        switch keyDecodingStrategy {
        case .useDefaultKeys:
            codingKey = key

        case .convertFromKebabCase:
            codingKey = key.kebabCaseToCamelCase()
        }

        return T(stringValue: codingKey)
    }
}

// MARK: - Unkeyed Decoding Container

private struct XMLUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    // The nodes from which this container is decoding
    let nodes: [XMLNode]

    // The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]

    // The index of the element being decoded.
    var currentIndex: Int = 0

    // Decoding configuration
    let keyDecodingStrategy: XMLStreamDecoder.KeyDecodingStrategy

    var count: Int? {
        return nodes.count
    }

    var isAtEnd: Bool {
        return currentIndex >= nodes.count
    }

    // MARK: - UnkeyedDecodingContainer Methods

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any?.self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed container is at end."
            ))
        }

        let node = nodes[currentIndex]
        let result = node.stringValue == nil && node.children.isEmpty && node.attributes.isEmpty
        if result {
            currentIndex += 1
        }

        return result
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: String.Type) throws -> String {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: Double.Type) throws -> Double {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: Float.Type) throws -> Float {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: Int.Type) throws -> Int {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try decodePrimitive(type)
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try decodePrimitive(type)
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed container is at end."
            ))
        }

        let node = self.nodes[currentIndex]
        let newPath = codingPath + [_XMLCodingKey(index: currentIndex)]

        // Decode using a single value container for primitives or a decoder for complex types
        if let stringValue = node.stringValue, isPrimitive(type) {
            let container = XMLSingleValueDecodingContainer(
                value: stringValue,
                codingPath: newPath,
            )
            currentIndex += 1
            return try container.decode(type)
        } else {
            let decoder = _XMLStreamDecoder(
                node: node,
                codingPath: newPath,
                keyDecodingStrategy: keyDecodingStrategy,
            )
            currentIndex += 1
            return try T(from: decoder)
        }
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(KeyedDecodingContainer<NestedKey>.self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed container is at end."
            ))
        }

        let node = nodes[currentIndex]
        let newPath = codingPath + [_XMLCodingKey(index: currentIndex)]

        let container = XMLKeyedDecodingContainer<NestedKey>(
            node: node,
            codingPath: newPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )

        currentIndex += 1
        return KeyedDecodingContainer(container)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed container is at end."
            ))
        }

        let node = nodes[currentIndex]
        let newPath = codingPath + [_XMLCodingKey(index: currentIndex)]

        // In XML, nested unkeyed containers are child elements of the current element
        let container = XMLUnkeyedDecodingContainer(
            nodes: node.children,
            codingPath: newPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )

        currentIndex += 1
        return container
    }

    mutating func superDecoder() throws -> Decoder {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Decoder.self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed container is at end."
            ))
        }

        let node = nodes[currentIndex]
        let newPath = codingPath + [_XMLCodingKey(index: currentIndex)]

        let decoder = _XMLStreamDecoder(
            node: node,
            codingPath: newPath,
            keyDecodingStrategy: keyDecodingStrategy,
        )

        currentIndex += 1
        return decoder
    }

    // MARK: - Helper Methods
    private mutating func decodePrimitive<T>(_ type: T.Type) throws -> T where T: Decodable & LosslessStringConvertible {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed container is at end."
            ))
        }

        let node = nodes[currentIndex]
        guard let stringValue = node.stringValue else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath + [_XMLCodingKey(index: currentIndex)],
                debugDescription: "Expected \(type) value but found null instead."
            ))
        }

        guard let value = T(stringValue) else {
            throw DecodingError.typeMismatch(type, DecodingError.Context(
                codingPath: codingPath + [_XMLCodingKey(index: currentIndex)],
                debugDescription: "Could not convert element value \"\(stringValue)\" to type \(type)."
            ))
        }

        currentIndex += 1
        return value
    }

    private func isPrimitive<T>(_ type: T.Type) -> Bool {
        return type is LosslessStringConvertible.Type
    }
}

// MARK: - Single Value Decoding Container

private struct XMLSingleValueDecodingContainer: SingleValueDecodingContainer {
    // The node or string value from which this container is decoding.
    private let node: XMLNode?
    private let value: String?

    // The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]

    // Initialize with a node
    init(node: XMLNode, codingPath: [CodingKey]) {
        self.node = node
        self.value = node.stringValue
        self.codingPath = codingPath
    }

    // Initialize with a string value
    init(value: String, codingPath: [CodingKey]) {
        self.node = nil
        self.value = value
        self.codingPath = codingPath
    }

    // MARK: - SingleValueDecodingContainer Methods

    func decodeNil() -> Bool {
        return value == nil || value!.isEmpty
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard let stringValue = value else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(type) but found null instead."
            ))
        }

        // Handle special case for boolean values
        let lowerValue = stringValue.lowercased()
        if lowerValue == "true" || lowerValue == "yes" || lowerValue == "1" {
            return true
        } else if lowerValue == "false" || lowerValue == "no" || lowerValue == "0" {
            return false
        }

        guard let value = Bool(stringValue) else {
            throw DecodingError.typeMismatch(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Could not convert value \"\(stringValue)\" to type \(type)."
            ))
        }

        return value
    }

    func decode(_ type: String.Type) throws -> String {
        guard let stringValue = value else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(type) but found null instead."
            ))
        }

        return stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard let stringValue = value, !stringValue.isEmpty else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(type) but found null instead."
            ))
        }

        guard let value = Double(stringValue) else {
            throw DecodingError.typeMismatch(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Could not convert value \"\(stringValue)\" to type \(type)."
            ))
        }
        return value
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard let stringValue = value, !stringValue.isEmpty else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(type) but found null instead."
            ))
        }

        // Handle non-conforming float values
        guard let value = Float(stringValue) else {
            throw DecodingError.typeMismatch(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Could not convert value \"\(stringValue)\" to type \(type)."
            ))
        }
        return value
    }

    func decode(_ type: Int.Type) throws -> Int {
        try decodePrimitive(type)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try decodePrimitive(type)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try decodePrimitive(type)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try decodePrimitive(type)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try decodePrimitive(type)
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try decodePrimitive(type)
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decodePrimitive(type)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decodePrimitive(type)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decodePrimitive(type)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try decodePrimitive(type)
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        if let decodable = type as? LosslessStringConvertible.Type {
            guard let stringValue = value, !stringValue.isEmpty else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected \(type) but found null instead."
                ))
            }

            let trimmedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = decodable.init(trimmedValue) else {
                throw DecodingError.typeMismatch(type, DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Could not convert value \"\(trimmedValue)\" to type \(type)."
                ))
            }

            if let value = value as? T {
                return value
            }
        }

        // For complex types, create a new decoder and let Decodable handle it
        if let node = node {
            let decoder = _XMLStreamDecoder(
                node: node,
                codingPath: codingPath,
                keyDecodingStrategy: .useDefaultKeys,
            )

            return try T(from: decoder)
        } else {
            throw DecodingError.typeMismatch(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot decode \(type) from simple value."
            ))
        }
    }

    // MARK: - Helper Methods
    private func decodePrimitive<T>(_ type: T.Type) throws -> T where T: Decodable & LosslessStringConvertible {
        guard let stringValue = value, !stringValue.isEmpty else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(type) but found null instead."
            ))
        }

        let trimmedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = T(trimmedValue) else {
            throw DecodingError.typeMismatch(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Could not convert value \"\(trimmedValue)\" to type \(type)."
            ))
        }

        return value
    }
}

// MARK: - Utility Extensions

private extension String {
    func kebabCaseToCamelCase() -> String {
        let parts = self.components(separatedBy: "-")
        guard let first = parts.first else { return self }

        let rest = parts.dropFirst().map { $0.capitalized }
        return ([first] + rest).joined()
    }

    func snakeCaseToCamelCase() -> String {
        let parts = self.components(separatedBy: "_")
        guard let first = parts.first else { return self }

        let rest = parts.dropFirst().map { $0.capitalized }
        return ([first] + rest).joined()
    }
}

private extension Date {
    init?(iso8601String: String) {
        if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
            if let date = ISO8601DateFormatter().date(from: iso8601String) {
                self = date
                return
            }
        }

        // Fallback for older OSes
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = formatter.date(from: iso8601String) {
            self = date
            return
        }

        return nil
    }
}

// MARK: - XML Coding Key

private struct _XMLCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
}
