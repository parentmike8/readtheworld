#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appRoot = repoRoot.appendingPathComponent("apps/app")

let ink = NSColor(calibratedRed: 0x21 / 255, green: 0x1F / 255, blue: 0x1A / 255, alpha: 1)
let paper = NSColor(calibratedRed: 0xF3 / 255, green: 0xF0 / 255, blue: 0xE9 / 255, alpha: 1)
let clay = NSColor(calibratedRed: 0xB0 / 255, green: 0x6A / 255, blue: 0x47 / 255, alpha: 1)

struct IconTarget {
  let relativePath: String
  let size: Int
}

let targets: [IconTarget] = [
  IconTarget(relativePath: "web/favicon.png", size: 64),
  IconTarget(relativePath: "web/icons/Icon-192.png", size: 192),
  IconTarget(relativePath: "web/icons/Icon-512.png", size: 512),
  IconTarget(relativePath: "web/icons/Icon-maskable-192.png", size: 192),
  IconTarget(relativePath: "web/icons/Icon-maskable-512.png", size: 512),
  IconTarget(relativePath: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", size: 48),
  IconTarget(relativePath: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", size: 72),
  IconTarget(relativePath: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", size: 96),
  IconTarget(relativePath: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", size: 144),
  IconTarget(relativePath: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", size: 192),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png", size: 20),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png", size: 40),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png", size: 60),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png", size: 29),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png", size: 58),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png", size: 87),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png", size: 40),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png", size: 80),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png", size: 120),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png", size: 120),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png", size: 180),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png", size: 76),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png", size: 152),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png", size: 167),
  IconTarget(relativePath: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png", size: 1024),
]

func font(named name: String, size: CGFloat) -> NSFont {
  NSFont(name: name, size: size) ?? NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size, weight: .medium)
}

func textSize(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGSize {
  (text as NSString).size(withAttributes: attributes)
}

func renderIcon(size: Int, to output: URL) throws {
  guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  ) else {
    throw NSError(domain: "ReadTheWorldIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context for \(output.path)"])
  }

  let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = graphicsContext

  ink.setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()

  let markFont = font(named: "Georgia", size: CGFloat(size) * 0.58)
  let periodFont = font(named: "Georgia", size: CGFloat(size) * 0.54)
  let markAttributes: [NSAttributedString.Key: Any] = [
    .font: markFont,
    .foregroundColor: paper,
    .kern: -CGFloat(size) * 0.015,
  ]
  let periodAttributes: [NSAttributedString.Key: Any] = [
    .font: periodFont,
    .foregroundColor: clay,
    .kern: -CGFloat(size) * 0.02,
  ]

  let mark = "r"
  let period = "."
  let markSize = textSize(mark, attributes: markAttributes)
  let periodSize = textSize(period, attributes: periodAttributes)
  let totalWidth = markSize.width + periodSize.width * 0.72
  let maxHeight = max(markSize.height, periodSize.height)
  let x = (CGFloat(size) - totalWidth) / 2
  let y = (CGFloat(size) - maxHeight) / 2 + CGFloat(size) * 0.04

  (mark as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: markAttributes)
  (period as NSString).draw(
    at: NSPoint(x: x + markSize.width - CGFloat(size) * 0.03, y: y),
    withAttributes: periodAttributes
  )

  NSGraphicsContext.restoreGraphicsState()

  guard let image = context.makeImage() else {
    throw NSError(domain: "ReadTheWorldIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not render \(output.path)"])
  }

  try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
  guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
  ) else {
    throw NSError(domain: "ReadTheWorldIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination for \(output.path)"])
  }
  CGImageDestinationAddImage(destination, image, nil)
  if !CGImageDestinationFinalize(destination) {
    throw NSError(domain: "ReadTheWorldIcon", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not write \(output.path)"])
  }
}

for target in targets {
  let output = appRoot.appendingPathComponent(target.relativePath)
  try renderIcon(size: target.size, to: output)
  print("Wrote \(target.relativePath)")
}
