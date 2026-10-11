import Testing
@testable import SitchCore

@Test func demoDocumentRenders() throws {
    let doc = try #require(DemoDocument.document())
    let image = try #require(Renderer.renderToImage(doc, spotlightDim: 0.55))
    #expect(image.width == DemoDocument.width && image.height == DemoDocument.height)
}
