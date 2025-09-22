/**
 * Semantic Release configuration for JoJoPing
 * - Analyzes commits on main and tags releases following Conventional Commits
 * - Creates GitHub releases (artifacts are uploaded by GitHub Actions workflow)
 */

module.exports = {
  branches: ["main"],
  plugins: [
    ["@semantic-release/commit-analyzer", { preset: "conventionalcommits" }],
    ["@semantic-release/release-notes-generator", { preset: "conventionalcommits" }],
    "@semantic-release/github"
  ]
};
