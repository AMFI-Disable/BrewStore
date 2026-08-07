# BrewStore Website

This is the static Vercel-ready download page for BrewStore.

## Deploy

Set the Vercel project root directory to `website`, or deploy the repository root with the root `vercel.json` configuration. Run `scripts/build-dmg.sh` first when the downloadable DMG should be served from `website/downloads`.

The versioned 1.0.0 DMG is checked into `website/downloads` so a Vercel deployment connected to GitHub can serve it directly. Publish the same artifact to the GitHub release and update the cask checksum for every new version.
