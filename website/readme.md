# BrewStore Website

This is the static Vercel-ready download page for BrewStore.

## Deploy

Set the Vercel project root directory to `website`, or deploy the repository root with the root `vercel.json` configuration. Run `scripts/build-dmg.sh` first when the downloadable DMG should be served from `website/downloads`.

The DMG is intentionally ignored by Git. Publish the same artifact to the GitHub release and upload it to the Vercel deployment when the download page is deployed.
