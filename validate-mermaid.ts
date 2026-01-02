#!/usr/bin/env bun

/**
 * Quick Mermaid validator using bunx and @mermaid-js/mermaid-cli.
 *
 * Usage:
 *   bun validate-mermaid.ts path/to/diagram.mmd
 */

const [, , inputPath] = process.argv

if (!inputPath) {
  console.error("Usage: bun validate-mermaid.ts <path-to-mermaid-file>")
  process.exit(1)
}

const proc = Bun.spawn({
  cmd: [
    "bunx",
    "@mermaid-js/mermaid-cli",
    "-i",
    inputPath,
    "-o",
    "/tmp/mermaid-validate.svg",
  ],
  stdout: "inherit",
  stderr: "inherit",
})

const exitCode = await proc.exited

if (exitCode === 0) {
  console.log("Mermaid validation succeeded.")
} else {
  console.error("Mermaid validation failed with exit code", exitCode)
}

process.exit(exitCode)
