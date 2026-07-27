#!/usr/bin/env node
//
// Generates every shipped Klass Hero site icon from priv/brand/kh-mark.svg.
//
//     node priv/brand/generate_icons.mjs
//
// Outputs (all committed to git — they are release artifacts, not build output;
// nothing in mix assets.deploy produces them):
//
//     priv/static/favicon.ico                    16 / 32 / 48, PNG-in-ICO
//     priv/static/images/icon.svg                vector, Chromium + Firefox
//     priv/static/images/apple-touch-icon.png    180x180, opaque, square
//
// WHY THIS EXISTS
//
// The bug this fixes (#1159) was created by hand-exporting a binary with no
// tracked source: commit 1dcdbb2c squeezed the 5.5:1 wordmark into a square,
// saved it at 8bpp, and shipped it. Nothing could catch that, because there was
// nothing upstream of the bytes to check. So the icons are now a pure function
// of one vector plus the constants below.
//
// NO DEPENDENCIES. The repo has zero npm footprint (there is no
// assets/package.json — tailwind and esbuild come from Hex escripts), and this
// script deliberately keeps it that way: rasterising goes through the Chrome
// binary, and the ICO container is written by hand against the spec.
//
// WHY PNG-IN-ICO
//
// Since Vista, an ICO entry's payload may be a whole PNG rather than a legacy
// BMP/DIB with a separate 1-bit AND transparency mask. Every browser favicon
// decoder handles it. It also makes the original defect *structurally*
// unreachable: there is no palette and no AND mask to clip antialiased strokes.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO = path.resolve(HERE, '..', '..')
const SOURCE = path.join(HERE, 'kh-mark.svg')
const STATIC = path.join(REPO, 'priv', 'static')

// ---------------------------------------------------------------------------
// Palette
//
// Tokens mirror assets/css/app.css. Swapping the whole look is a change here
// and a re-run — geometry in kh-mark.svg is untouched either way.
// ---------------------------------------------------------------------------

const TOKENS = {
  heroBlue: '#0FC3FF', // --color-hero-blue-500
  heroYellow: '#FFFF36', // --color-hero-yellow-500
  heroBlack: '#000000' // --color-hero-black
}

// Yellow tile, cyan monogram — the two landing-bar logo colours, with the
// letterforms keeping the brand cyan. No outline pass: a third colour on a
// two-colour mark reads as noise at tab size.
//
// `outline: null` disables the outline pass entirely, which makes
// OUTLINE_MIN_SIZE below inert for this palette. It is kept because it is a
// property of the treatment, not of this particular colour choice.
const VARIANT = {
  tile: TOKENS.heroYellow,
  fill: TOKENS.heroBlue,
  outline: null
}

const FILL_WIDTH = 8
const OUTLINE_WIDTH = 11
const TILE_RADIUS = 12 // on the 64-unit viewBox

// ---------------------------------------------------------------------------
// Per-size treatment
//
// Small icons are hand-tuned, not downscaled. At 16px a stroke lands around
// 2px, and the outline pass only adds 1.5px per side — below the threshold it
// stops reading as an outline and just muddies the letterforms, so it is
// dropped and the fill carries the mark alone.
//
// Apple touch icons are masked and rounded by iOS itself, so that one ships
// square and fully opaque; rounding it here would show as a dark fringe inside
// the system's own corner radius.
// ---------------------------------------------------------------------------

const OUTLINE_MIN_SIZE = 24

const treatmentFor = (size, { square = false } = {}) => ({
  outline: Boolean(VARIANT.outline) && size >= OUTLINE_MIN_SIZE,
  radius: square ? 0 : TILE_RADIUS
})

const ICO_SIZES = [16, 32, 48]
const APPLE_TOUCH_SIZE = 180

// ---------------------------------------------------------------------------
// Source geometry
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// SVG composition
// ---------------------------------------------------------------------------

const strokeGroup = (paths, color, width) =>
  `<g fill="none" stroke="${color}" stroke-width="${width}" ` +
  `stroke-linecap="round" stroke-linejoin="round">` +
  paths.map((d) => `<path d="${d}"/>`).join('') +
  `</g>`

function composeSvg(paths, size, opts = {}) {
  const { outline, radius } = treatmentFor(size, opts)

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

// ---------------------------------------------------------------------------
// Rasterisation via headless Chrome
//
// Chrome is the renderer the icons are actually consumed by, it needs no npm
// dependency, and the same binary exists on Linux CI images.
// ---------------------------------------------------------------------------

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
  // The SVG is inlined as a data URI inside a page sized exactly to the target,
  // so the screenshot needs no cropping and no device-scale correction.
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

// ---------------------------------------------------------------------------
// PNG / ICO
// ---------------------------------------------------------------------------

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

// ICO container. 6-byte ICONDIR, then one 16-byte ICONDIRENTRY per image,
// then the payloads. Offsets are absolute from the start of the file.
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
    e.writeUInt8(size === 256 ? 0 : size, 0) // width, 0 means 256
    e.writeUInt8(size === 256 ? 0 : size, 1) // height
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

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

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
    // Vector icon. Chromium and Firefox prefer this; Safari ignores SVG
    // favicons entirely, which is exactly why the .ico below still has to be
    // correct rather than a token fallback.
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

    if (VARIANT.outline) {
      const outlined = ICO_SIZES.filter((size) => size >= OUTLINE_MIN_SIZE)
      console.log(
        `\noutline applied at ${outlined.join('/')}px, dropped below ${OUTLINE_MIN_SIZE}px`
      )
    } else {
      console.log(`\nno outline pass — this variant is two-colour`)
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
}

main()
