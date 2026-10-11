import CoreGraphics
import Foundation
import Testing
@testable import SitchCore

private func solidImage(_ w: Int, _ h: Int, _ c: RGBAColor = .white) -> CGImage {
    let ctx = Draw.makeContext(width: w, height: h)!
    ctx.setFillColor(c.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// RGBA of one pixel (top-left origin) of an image.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    return (px[0], px[1], px[2], px[3])
}

@Test func demoDocumentRenders() throws {
    let doc = try #require(DemoDocument.document())
    let image = try #require(Renderer.renderToImage(doc, spotlightDim: 0.55))
    #expect(image.width == DemoDocument.width && image.height == DemoDocument.height)
}

@Test func renderIsTopLeftOrigin() throws {
    // A black box in the top-left corner must land in the top-left of the output.
    let doc = Document(base: solidImage(100, 50))
    let box = BoxAnnotation()
    box.a = CGPoint(x: 0, y: 0); box.b = CGPoint(x: 20, y: 10); box.filled = true; box.color = .black
    doc.annotations = [box]
    let out = try #require(Renderer.renderToImage(doc, spotlightDim: 0.5))
    #expect(pixel(out, 5, 5).0 < 10)
    #expect(pixel(out, 5, 45).0 > 245)
}

@Test func cropRendersViewport() throws {
    let doc = Document(base: solidImage(200, 100))
    doc.applyCrop(PixelRect(x: 10, y: 20, width: 50, height: 30))
    let out = try #require(Renderer.renderToImage(doc, spotlightDim: 0.5))
    #expect(out.width == 50 && out.height == 30)
}

@Test func cropClampsAndFullCropClears() {
    let doc = Document(base: solidImage(200, 100))
    doc.applyCrop(PixelRect(x: 150, y: 80, width: 500, height: 500))
    #expect(doc.viewRect == PixelRect(x: 150, y: 80, width: 50, height: 20))
    doc.applyCrop(PixelRect(x: 0, y: 0, width: 200, height: 100))
    #expect(doc.crop == nil)
}

@Test func undoRedoRestoresClonesAndDirty() {
    let doc = Document(base: solidImage(10, 10))
    let line = LineAnnotation()
    doc.add(line)
    #expect(doc.annotations.count == 1 && doc.canUndo)
    doc.undo()
    #expect(doc.annotations.isEmpty && doc.canRedo && doc.isPristine)
    doc.redo()
    #expect(doc.annotations.count == 1)
    // Restored objects are clones: the canvas must drop selections pointing at the old one.
    #expect(doc.annotations[0] !== line)
}

@Test func undoDepthIsBounded() {
    let doc = Document(base: solidImage(10, 10))
    for _ in 0..<150 { doc.add(LineAnnotation()) }
    var steps = 0
    while doc.canUndo { doc.undo(); steps += 1 }
    #expect(steps == 100)
}

@Test func rotateRightMapsImageAndAnnotations() throws {
    // 4×2 image, top-left pixel red; after rotating right it is the top-right pixel of a 2×4 image.
    let ctx = Draw.makeContext(width: 4, height: 2)!
    ctx.setFillColor(RGBAColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
    ctx.setFillColor(RGBAColor(255, 0, 0).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    let doc = Document(base: ctx.makeImage()!)
    let stamp = StampAnnotation()
    stamp.center = CGPoint(x: 1, y: 0.5)
    doc.annotations = [stamp]
    doc.rotateFlip(.rotateRight)
    #expect(doc.width == 2 && doc.height == 4)
    #expect(pixel(doc.base, 1, 0) == (255, 0, 0, 255))
    #expect(stamp.center == CGPoint(x: 1.5, y: 1))
    #expect(doc.baseVersion == 1)
}

@Test func flipsAndRotateLeftRoundTrip() {
    let doc = Document(base: solidImage(30, 20))
    let arrow = ArrowAnnotation()
    arrow.a = CGPoint(x: 3, y: 4); arrow.b = CGPoint(x: 25, y: 15)
    doc.annotations = [arrow]
    doc.rotateFlip(.rotateLeft)
    doc.rotateFlip(.rotateRight)
    doc.rotateFlip(.flipHorizontal)
    doc.rotateFlip(.flipHorizontal)
    doc.rotateFlip(.flipVertical)
    doc.rotateFlip(.flipVertical)
    #expect(arrow.a == CGPoint(x: 3, y: 4) && arrow.b == CGPoint(x: 25, y: 15))
    #expect(doc.width == 30 && doc.height == 20)
}

@Test func pixelateAveragesBlocks() throws {
    let img = solidImage(40, 40, RGBAColor(10, 200, 30))
    let out = try #require(EffectRenderer.pixelate(img, PixelRect(x: 5, y: 5, width: 30, height: 20)))
    #expect(out.width == 30 && out.height == 20)
    #expect(pixel(out, 12, 12) == (10, 200, 30, 255))
}

@Test func blurKeepsUniformColor() throws {
    let img = solidImage(60, 30, RGBAColor(90, 90, 90))
    let out = try #require(EffectRenderer.boxBlur(img, PixelRect(x: 0, y: 0, width: 60, height: 30), radius: 12))
    #expect(pixel(out, 30, 15) == (90, 90, 90, 255))
}

@Test func spotlightDimsOutsideOnly() throws {
    let doc = Document(base: solidImage(100, 100))
    let s1 = SpotlightAnnotation(); s1.a = CGPoint(x: 0, y: 0); s1.b = CGPoint(x: 40, y: 40)
    let s2 = SpotlightAnnotation(); s2.a = CGPoint(x: 20, y: 20); s2.b = CGPoint(x: 60, y: 60)
    doc.annotations = [s1, s2]
    let out = try #require(Renderer.renderToImage(doc, spotlightDim: 0.5))
    #expect(pixel(out, 30, 30).0 > 245) // overlap of two spotlights stays bright
    #expect(pixel(out, 90, 90).0 < 140)
}

@Test func hitTesting() {
    let box = BoxAnnotation()
    box.a = CGPoint(x: 10, y: 10); box.b = CGPoint(x: 110, y: 60)
    #expect(box.hitTest(CGPoint(x: 10, y: 30)))      // on the outline
    #expect(!box.hitTest(CGPoint(x: 60, y: 35)))     // hollow middle
    box.filled = true
    #expect(box.hitTest(CGPoint(x: 60, y: 35)))
    let line = LineAnnotation()
    line.a = .zero; line.b = CGPoint(x: 100, y: 0)
    #expect(line.hitTest(CGPoint(x: 50, y: 5)) && !line.hitTest(CGPoint(x: 50, y: 20)))
}

@Test func rectHandlesResize() {
    let r = BoxAnnotation()
    r.a = CGPoint(x: 10, y: 10); r.b = CGPoint(x: 50, y: 50)
    r.moveHandle(2, to: CGPoint(x: 80, y: 90))
    #expect(r.rect == CGRect(x: 10, y: 10, width: 70, height: 80))
    r.moveHandle(7, to: CGPoint(x: 0, y: 999))
    #expect(r.rect.minX == 0 && r.rect.height == 80)
}

@Test func hotkeyParsingAndFormatting() throws {
    let c = try #require(HotkeyChord.parse("Cmd+Opt+4"))
    #expect(c.modifiers == [.command, .option] && c.key == "4" && c.keyCode == 0x15)
    #expect(c.symbols == "⌥⌘4")
    #expect(c.description == "Opt+Cmd+4")
    #expect(HotkeyChord.parse(c.description) == c)
    #expect(HotkeyChord.parse("ctrl+shift+f13")?.keyCode == 0x69)
    #expect(HotkeyChord.parse("Cmd+Opt") == nil)
    #expect(HotkeyChord.parse("Cmd+Bogus") == nil)
    #expect(HotkeyChord.keyName(forKeyCode: 0x15) == "4")
}

@Test func colorHex() {
    #expect(RGBAColor(hex: "#FF3366") == .pink)
    #expect(RGBAColor(hex: "#80FF3366") == RGBAColor(0xFF, 0x33, 0x66, 0x80))
    #expect(RGBAColor.pink.hex == "#FF3366")
    #expect(RGBAColor(hex: "nope") == nil)
}

@Test func settingsRoundTripAndTolerantDecode() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = dir.appendingPathComponent("settings.json")
    #expect(SettingsStore.load(from: url).firstRun)

    var s = AppSettings()
    s.theme = "Dark"; s.lastRegion = PixelRect(x: 1, y: 2, width: 3, height: 4); s.timerSeconds = 5
    SettingsStore.save(s, to: url)
    let loaded = SettingsStore.load(from: url)
    #expect(!loaded.firstRun && loaded.settings == s)

    // A partial / mistyped file keeps defaults for the bad keys instead of resetting everything.
    try Data(#"{"theme":"Light","timerSeconds":"oops"}"#.utf8).write(to: url)
    let partial = SettingsStore.load(from: url).settings
    #expect(partial.theme == "Light" && partial.timerSeconds == 0 && partial.captureHotkey == "Cmd+Opt+4")
    try? FileManager.default.removeItem(at: dir)
}

@Test func textBoundsGrowWithText() {
    let t = TextAnnotation()
    t.fontSize = 28
    t.text = "Hi"
    let short = t.bounds.width
    t.text = "Hello there, longer"
    #expect(t.bounds.width > short)
    t.text = "one\ntwo"
    #expect(t.bounds.height > 28 * 1.8)
}
