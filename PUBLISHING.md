# Publishing

The Swift sources are shared by npm/CocoaPods and Swift Package Manager.
`package.json` is the version source of truth; the podspec reads it directly.
Use a matching bare semantic-version Git tag, e.g. `0.1.0` (no `v` prefix).
The npm scope and GitHub repository are configured destinations, not evidence
that either exists or that the current account has publication permission.

## Verify the artifact

On a Mac with Xcode 26+, Node/npm, Python 3, CocoaPods and the xcodeproj Ruby gem:

```sh
npm pack --dry-run
npm run verify:distribution
```

The verification installs a real npm tarball into an isolated host, resolves its
podspec from node_modules, builds a normally signed iOS Simulator application
through CocoaPods, and builds the same installed source through SPM. Logs and the
tarball are saved under `.artifacts/distribution`. No registry publication occurs.
The package intentionally has no install scripts, JavaScript entry point, or
runtime npm dependencies. It exposes `package.json` for native path resolution.

Run the behavioral suite (`python3 scripts/verify.py`) when native behavior changes.
This packaging check does not replace keyboard or visual acceptance.

## Release

1. Confirm access to the configured npm scope. For a remote SPM release, also
   confirm the Git repository and its remote. If choosing different destinations,
   update package.json, podspec source, and documentation together before verification.
2. Update package.json's version. Review the license, source changes, and package
   file list. Repeat artifact verification at that exact version.
3. Commit the reviewed release and tag it with the same version. Publishing to
   npm does not require a Git push. A remote SPM release additionally requires
   pushing the commit and tag to the configured repository; SPM resolves that tag.
4. Authenticate to npm using the account's supported login method and publish the
   verified tarball, not a newly packed working tree:

   ```sh
   npm publish .artifacts/distribution/rien7-anchored-overlay-kit-0.1.0.tgz --access public
   ```

5. Check the registry version/integrity and test installation of that registry
   version before announcing the release.

The filename above is an example for version 0.1.0. Use the actual filename in
`pack.json`. Never reuse an already published npm version. No CocoaPods trunk
release is required: npm consumers use a local-path podspec. Any Git-only pod
release must include package.json because the podspec reads its version there.
