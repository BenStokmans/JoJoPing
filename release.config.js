/**
 * Semantic Release configuration for JoJoPing
 * - Analyzes commits on main and tags releases following Conventional Commits
 * - Builds the macOS app DMG and the Raycast extension zip
 * - Uploads both artifacts to the GitHub Release
 */

const path = require("path");

module.exports = {
  branches: ["main"],
  plugins: [
    ["@semantic-release/commit-analyzer", { preset: "conventionalcommits" }],
    ["@semantic-release/release-notes-generator", { preset: "conventionalcommits" }],
    [
      "@semantic-release/exec",
      {
        prepareCmd:
          "export APP_VERSION=${nextRelease.version} && bash scripts/ci-prepare.sh",
        // Build after version is determined, before publish
        publishCmd:
          "export APP_VERSION=${nextRelease.version} && bash scripts/ci-build-and-package.sh"
      }
    ],
    [
      "@semantic-release/github",
      {
        // Use globs; build script cleans old artifacts so only current ones remain
        assets: [
          "build/JoJoPing-*.dmg",
          "build/jojoping-raycast-*.zip"
        ]
      }
    ]
  ]
};
