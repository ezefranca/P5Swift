# Photos and Privacy

Save images and movies through an explicit, permission-aware Photos workflow.

## Ask only after a user action

``P5PhotoLibrary`` separates status checks, authorization requests, and saves. Neither
``P5PhotoLibrary/authorizationStatus(for:)`` nor either save method presents a system
prompt. Call ``P5PhotoLibrary/requestAuthorization(for:)`` from a visible action such as
a Save to Photos button:

```swift
let photos = P5PhotoLibrary()
let status = try await photos.requestAuthorization(for: .addOnly)

guard status == .authorized || status == .limited else {
    return
}

let identifier = try await photos.save(image, as: .png)
```

Use `.addOnly` unless the application genuinely needs to inspect existing assets. Add-only
access requires `NSPhotoLibraryAddUsageDescription` in the host application's information
property list. Read-write access requires `NSPhotoLibraryUsageDescription`. Swift packages
cannot supply truthful, application-specific purpose text on behalf of their clients.

If status is `.notDetermined`, saving throws
``P5PhotoLibraryError/authorizationNotDetermined`` rather than requesting access. Restricted,
denied, and unknown future statuses produce
``P5PhotoLibraryError/accessUnavailable(_:)``. Limited read-write authorization can still add
assets.

## Save images and movies

Image saves encode through ImageIO before opening a Photos change transaction. PNG preserves
alpha; JPEG and HEIF use the requested quality. A successful save returns the asset's Photos
local identifier.

```swift
let imageID = try await photos.save(image, as: .heif, quality: 0.85)
let movieID = try await photos.saveVideo(at: exportedMovieURL)
```

Movie input must be an existing regular local file. Saving never deletes or rewrites it.
Photos transactions cannot be cancelled after submission; both authorization and save APIs
observe task cancellation before handing control to the system and authorization observes it
again after the system responds.

## Privacy manifest

P5 ships a package privacy manifest declaring no tracking or package-level data collection.
It declares the System Boot Time required-reason API because monotonic uptime drives sketch
timing and input timestamps. Photos content stays within the user-requested on-device Photos
transaction; P5 does not transmit it.

The host application remains responsible for its complete privacy manifest, purpose strings,
data-use disclosure, and App Store privacy answers. Those declarations must reflect the whole
application, including how it uses images, models, networking, and any future camera or
microphone integration.
