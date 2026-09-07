# Provider marks

These marks identify the usage provider in the rotating menu-bar item. They are
not the application logo and do not imply endorsement.

- `OpenAI.svg`: black monoblossom from OpenAI’s official logo package:
  https://cdn.openai.com/brand/OpenAI-Logos-2025.zip
  Brand guidance: https://openai.com/brand/
  The OpenAI mark belongs to OpenAI and is not covered by this repository’s MIT license.
- `Claude.svg`: Claude starburst vector from LobeHub Icons:
  https://github.com/lobehub/lobe-icons/blob/master/packages/static-svg/icons/claude.svg
  Its source license is included in `LICENSE-LobeHub`. The Claude mark belongs to Anthropic.

Retrieved 2026-09-07 UTC. The PDFs preserve the SVG path geometry as vectors,
centered in an 18-point square using the visible mark bounds. They contain no
screenshot backgrounds or user-provided screenshot metadata. macOS renders their
alpha masks as monochrome template images.

The PDFs, this attribution, and the LobeHub license are copied into the application
bundle. The source SVGs stay in the repository for review. The conversion used pdf-lib’s
`drawSvgPath` with black fill: OpenAI bounds (118.557,119.958,484.139,479.818),
Claude bounds (0,0,24,24), uniformly scaled to fit 18×18 points.
