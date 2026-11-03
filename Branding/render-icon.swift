// Renders an Icon Composer `.icon` exactly as macOS draws it (Liquid Glass and
// all) into an `.iconset` folder: compiles it with actool into a throwaway
// bundle, then asks IconServices (NSWorkspace) for the icon at each size.
//
// usage: swift render-icon.swift <AppIcon.icon> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <AppIcon.icon> <out.iconset>\n".utf8))
    exit(64)
}
let icon = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])

func run(_ tool: String, _ arguments: [String], required: Bool = true) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try! process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 || !required else { fatalError("\(tool) failed") }
}

let fileManager = FileManager.default
let id = UUID().uuidString
let scratch = fileManager.temporaryDirectory.appendingPathComponent("render-icon-\(id)")
let app = scratch.appendingPathComponent("IconPreview.app")
let resources = app.appendingPathComponent("Contents/Resources")
let executable = app.appendingPathComponent("Contents/MacOS/IconPreview")
try! fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
try! fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
defer {
    // Best effort: LaunchServices occasionally refuses to unregister a bundle it
    // has not finished indexing; the scratch copy is deleted either way.
    run(lsregister, ["-u", app.path], required: false)
    try? fileManager.removeItem(at: scratch)
}

run("/usr/bin/xcrun", [
    "actool", icon.path, "--compile", resources.path, "--platform", "macosx",
    "--minimum-deployment-target", "26.0", "--app-icon", (icon.lastPathComponent as NSString).deletingPathExtension,
    "--output-partial-info-plist", scratch.appendingPathComponent("partial.plist").path,
])
// A fresh bundle id per run so IconServices never serves a cached icon.
let info: [String: Any] = [
    "CFBundleIdentifier": "ai.copera.currency.icon-preview.\(id)",
    "CFBundlePackageType": "APPL",
    "CFBundleExecutable": "IconPreview",
    "CFBundleIconName": "AppIcon",
    "CFBundleIconFile": "AppIcon",
]
let plist = try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
try! plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
// A runnable, signed bundle; otherwise Finder badges the icon as "can't open".
try! fileManager.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])

let image = NSWorkspace.shared.icon(forFile: app.path)
try! fileManager.createDirectory(at: out, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
