# BrewStore Website

This is the static Vercel-ready download page for BrewStore.

## Deploy

Set the Vercel project root directory to `website`, or deploy the repository root with the root `vercel.json` configuration. Run `scripts/build-dmg.sh` first when the downloadable DMG should be served from `website/downloads`.

The versioned 1.0.0 DMG is checked into `website/downloads` so a Vercel deployment connected to GitHub can serve it directly. Public release is intentionally paused while the release account is unavailable. Do not publish the checked-in DMG as a final release until the app has passed XCTest on a healthy host and the replacement artifact has been signed, notarized, and checksum-verified.
