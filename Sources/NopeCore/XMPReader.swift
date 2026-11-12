import Foundation

/// Lists the top-level properties of an XMP packet.
///
/// Written from XMP part 1 (ISO 16684-1), section 7: properties are the children of each
/// `rdf:Description` element, or its attributes other than `rdf:about` and namespace
/// declarations. Nested structures count as their top-level property only. Uses Foundation's
/// `XMLParser`, which doesn't fetch external entities unless asked
/// (`shouldResolveExternalEntities` is `false` by default). A packet that isn't well-formed XML
/// produces a problem, so the file is rejected.
final class XMPReader: NSObject, XMLParserDelegate {
    /// The RDF namespace URI.
    static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    /// What has been found so far.
    private var inventory = MetadataInventory()
    /// The depth of the current element below the nearest `rdf:Description`, or `nil` outside
    /// one.
    private var depthInDescription: Int?
    /// The property being read: namespace, name and text so far.
    private var current: (namespace: String, name: String, text: String)?

    /// Reads an XMP packet.
    ///
    /// - Parameter bytes: The packet, as UTF-8 XML.
    /// - Returns: Every top-level property, or a problem if the packet can't be parsed.
    static func read(_ bytes: [UInt8]) -> MetadataInventory {
        let reader = XMPReader()
        let parser = XMLParser(data: Data(bytes))
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        if !parser.parse() { reader.inventory.problems.append("XMP: the packet isn't well-formed XML") }
        return reader.inventory
    }

    /// Starts an element: a `rdf:Description`, or a property inside one.
    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if let depth = depthInDescription {
            // An element with no namespace is recorded with an empty namespace URI.
            if depth == 0 { current = ([namespaceURI].compactMap { $0 }.joined(), elementName, "") }
            depthInDescription = depth + 1
            return
        }
        guard namespaceURI == Self.rdfNamespace, elementName == "Description" else { return }
        depthInDescription = 0
        // With namespace processing on, XMLParser reports attributes by qualified name, without
        // their namespace URI, so an attribute property is recorded by its qualified name.
        for (name, value) in attributes.sorted(by: { $0.key < $1.key }) where name != "rdf:about" {
            inventory.xmpProperties.append(MetadataInventory.XMPProperty(namespace: "", name: name, value: value))
        }
    }

    /// Collects a property's text.
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current?.text += string
    }

    /// Ends an element, recording a finished top-level property.
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard let depth = depthInDescription else { return }
        if depth == 0 {
            depthInDescription = nil
            return
        }
        depthInDescription = depth - 1
        if depth == 1, let property = current {
            let value = property.text.trimmingCharacters(in: .whitespacesAndNewlines)
            inventory.xmpProperties.append(
                MetadataInventory.XMPProperty(namespace: property.namespace, name: property.name, value: value))
            current = nil
        }
    }
}
