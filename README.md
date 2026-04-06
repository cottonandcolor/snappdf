# SnapPDF

An iOS app to scan documents by taking photos, adjusting crop boundaries, and saving as PDF.

## Features

- **Camera Capture** — Point your camera at any page and take a photo
- **Auto Edge Detection** — Automatically detects document boundaries using Vision framework
- **Draggable Corners** — Manually adjust the 4 corner handles to fine-tune the crop area
- **Perspective Correction** — Straightens the document using Core Image
- **Multi-Page PDFs** — Scan multiple pages into a single PDF
- **Save & Share** — PDFs saved locally; share via any app using the share sheet
- **Rename & Delete** — Manage your scanned documents from the home screen

## Xcode Setup

1. **Create a new Xcode project**
   - Open Xcode → File → New → Project
   - Choose **App** under iOS
   - Product Name: `SnapPDF`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Minimum Deployment: **iOS 16.0**

2. **Replace the generated files**
   - Delete the auto-generated `ContentView.swift` from the project
   - Drag all `.swift` files from the `SnapPDF/` folder into your Xcode project navigator
   - Make sure "Copy items if needed" is checked

3. **Add Camera Permission**
   - Select your project in the navigator → select the **SnapPDF** target
   - Go to the **Info** tab
   - Add a new key: `NSCameraUsageDescription`
   - Value: `SnapPDF needs camera access to scan documents`

4. **Build & Run**
   - Select a physical device (camera is not available in the Simulator)
   - Press **Cmd + R** to build and run

## App Flow

```
Home Screen → Tap Camera → Take Photo → Adjust Corners → Create PDF
                                                          ↓
                                              Review Pages → Add More / Save PDF
```

## Requirements

- iOS 16.0+
- Xcode 15+
- Physical device (for camera)
