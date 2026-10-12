import Foundation

/// A shared model view: closing one indexer's view leaves the owner's model alive.
public final class BorrowedEmbedder: Embedder {
    private let model: any Embedder
    public init(_ model: any Embedder) { self.model = model }
    public var info: WorkerInfo { model.info }
    public func embedTexts(_ texts: [String]) throws -> [[Float]] { try model.embedTexts(texts) }
    public func embedImages(_ paths: [String], budget: Int) throws -> [Embedding] {
        try model.embedImages(paths, budget: budget)
    }
    public func embedAudio(_ paths: [String]) throws -> [Embedding] { try model.embedAudio(paths) }
    public func close() {}
}
