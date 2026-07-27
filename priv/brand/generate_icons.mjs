#!/usr/bin/env node
//
// Regenerates every shipped site icon from kh-mark.svg:
//
//     node priv/brand/generate_icons.mjs
//
// Outputs are committed release artifacts — nothing in mix assets.deploy builds
// them. Zero npm dependencies by design (the repo has no package.json): Chrome
// rasterises, and the ICO container is written by hand against the spec.
//
// ICO entries carry whole PNGs rather than legacy BMP/DIB, so no palette and no
// 1-bit AND mask exist to clip antialiased strokes — the #1159 defect is
// structurally unreachable.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO = path.resolve(HERE, '..', '..')
const SOURCE = path.join(HERE, 'kh-mark.svg')
const STATIC = path.join(REPO, 'priv', 'static')

// Hex mirrors the oklch() tokens in assets/css/app.css — kept in sync by hand.
const TOKENS = {
  heroBlue: '#0FC3FF', // --color-hero-blue-500
  heroYellow: '#FFFF36' // --color-hero-yellow-500
}

// Yellow tile, cyan monogram — the two landing-bar logo colours. No outline
// pass: a third colour on a two-colour mark reads as noise at tab size.
const VARIANT = {
  tile: TOKENS.heroYellow,
  fill: TOKENS.heroBlue,
  outline: null
}

const FILL_WIDTH = 8
const OUTLINE_WIDTH = 11
const TILE_RADIUS = 12
const ICO_SIZES = [16, 32, 48]
const APPLE_TOUCH_SIZE = 180

// Below ~24px an outline adds under 2px per side, so it stops reading as an
// outline and just muddies the letterforms.
const OUTLINE_MIN_SIZE = 24

// iOS masks and rounds the apple-touch icon itself; rounding it here would show
// as a fringe inside the system's own corner radius.
const treatmentFor = (size, square) => ({
  outline: Boolean(VARIANT.outline) && size >= OUTLINE_MIN_SIZE,
  radius: square ? 0 : TILE_RADIUS
})

const EXPECTED_PATHS = 6 // K: stem + 2 diagonals. H: 2 stems + crossbar.

function readGeometry() {
  const svg = fs.readFileSync(SOURCE, 'utf8')
  const paths = [...svg.matchAll(/<path[^>]*\sd="([^"]+)"/g)].map((m) => m[1])

  if (paths.length !== EXPECTED_PATHS) {
    throw new Error(
      `kh-mark.svg: expected ${EXPECTED_PATHS} <path> elements, found ${paths.length}. ` +
        `If the monogram genuinely changed shape, update EXPECTED_PATHS.`
    )
  }
  return paths
}

const strokeGroup = (paths, color, width) =>
  `<g fill="none" stroke="${color}" stroke-width="${width}" ` +
  `stroke-linecap="round" stroke-linejoin="round">` +
  paths.map((d) => `<path d="${d}"/>`).join('') +
  `</g>`

function composeSvg(paths, size, { square = false } = {}) {
  const { outline, radius } = treatmentFor(size, square)

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" ` +
    `width="${size}" height="${size}">` +
    (VARIANT.tile
      ? `<rect width="64" height="64" rx="${radius}" fill="${VARIANT.tile}"/>`
      : '') +
    (outline ? strokeGroup(paths, VARIANT.outline, OUTLINE_WIDTH) : '') +
    strokeGroup(paths, VARIANT.fill, FILL_WIDTH) +
    `</svg>`
  )
}

// Chrome is the renderer these icons are actually consumed by, and the same
// binary exists on Linux CI images.
const CHROME_CANDIDATES = [
  process.env.CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser'
].filter(Boolean)

function findChrome() {
  const found = CHROME_CANDIDATES.find((p) => fs.existsSync(p))
  if (!found) {
    throw new Error(
      'No Chrome binary found. Set CHROME_BIN, or install Google Chrome / Chromium.\n' +
        `Looked in:\n  ${CHROME_CANDIDATES.join('\n  ')}`
    )
  }
  return found
}

function rasterize(chrome, svg, size, tmp) {
  const page = path.join(tmp, `page-${size}.html`)
  const out = path.join(tmp, `out-${size}.png`)
  const dataUri = `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`

  fs.writeFileSync(
    page,
    `<body style="margin:0;padding:0;width:${size}px;height:${size}px">` +
      `<img src="${dataUri}" width="${size}" height="${size}" style="display:block">` +
      `</body>`
  )

  execFileSync(
    chrome,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--default-background-color=00000000',
      `--screenshot=${out}`,
      `--window-size=${size},${size}`,
      page
    ],
    { stdio: 'ignore' }
  )

  const png = fs.readFileSync(out)
  assertPngSize(png, size)
  return png
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

function assertPngSize(png, size) {
  if (!png.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error('Rasteriser did not return a PNG')
  }
  // IHDR is always the first chunk: 8 sig + 4 length + 4 type, then w/h.
  const width = png.readUInt32BE(16)
  const height = png.readUInt32BE(20)
  if (width !== size || height !== size) {
    throw new Error(`Expected a ${size}x${size} PNG, got ${width}x${height}`)
  }
}

// 6-byte ICONDIR, one 16-byte ICONDIRENTRY per image, then the payloads.
// Offsets are absolute from the start of the file.
function buildIco(images) {
  const HEADER = 6
  const ENTRY = 16

  const dir = Buffer.alloc(HEADER)
  dir.writeUInt16LE(0, 0) // reserved
  dir.writeUInt16LE(1, 2) // type: 1 = icon
  dir.writeUInt16LE(images.length, 4)

  let offset = HEADER + ENTRY * images.length

  const entries = images.map(({ size, png }) => {
    const e = Buffer.alloc(ENTRY)
    const dim = size === 256 ? 0 : size // the spec encodes 256 as 0

    e.writeUInt8(dim, 0) // width
    e.writeUInt8(dim, 1) // height
    e.writeUInt8(0, 2) // palette entries — 0, this is truecolor
    e.writeUInt8(0, 3) // reserved
    e.writeUInt16LE(1, 4) // colour planes
    e.writeUInt16LE(32, 6) // bits per pixel — never 8, that was the bug
    e.writeUInt32LE(png.length, 8)
    e.writeUInt32LE(offset, 12)
    offset += png.length
    return e
  })

  return Buffer.concat([dir, ...entries, ...images.map((i) => i.png)])
}

function write(relative, data) {
  const target = path.join(STATIC, relative)
  fs.mkdirSync(path.dirname(target), { recursive: true })
  fs.writeFileSync(target, data)
  const kb = (data.length / 1024).toFixed(1)
  console.log(`  ${relative.padEnd(34)} ${String(data.length).padStart(7)} B  (${kb} kB)`)
}

function main() {
  const paths = readGeometry()
  const chrome = findChrome()
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kh-icons-'))

  console.log(`source  ${path.relative(REPO, SOURCE)}`)
  console.log(`chrome  ${chrome}\n`)

  try {
    // Safari ignores SVG favicons entirely, which is why the .ico below still
    // has to be correct rather than a token fallback.
    write('images/icon.svg', Buffer.from(composeSvg(paths, 64) + '\n'))

    const images = ICO_SIZES.map((size) => ({
      size,
      png: rasterize(chrome, composeSvg(paths, size), size, tmp)
    }))
    write('favicon.ico', buildIco(images))

    write(
      'images/apple-touch-icon.png',
      rasterize(
        chrome,
        composeSvg(paths, APPLE_TOUCH_SIZE, { square: true }),
        APPLE_TOUCH_SIZE,
        tmp
      )
    )
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
}

main()
