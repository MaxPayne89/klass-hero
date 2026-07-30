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
import { spawnSync } from 'node:child_process'
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

// Mirrors the landing wordmark (priv/static/images/logo.png): cyan letterforms,
// yellow outline, no field colour. Yellow is 1.07:1 on a white tab strip, so on
// a light tab the outline reads as almost nothing and the mark carries on the
// cyan alone — the same thing the wordmark does on a white page.
const VARIANT = {
  tile: null,
  fill: TOKENS.heroBlue,
  outline: TOKENS.heroYellow
}

// iOS composites a transparent apple-touch icon onto an unspecified background,
// so that one size gets an explicit tile rather than inheriting whatever the OS
// picks. Black keeps both brand colours at full contrast.
const APPLE_TOUCH_TILE = '#000000'

const FILL_WIDTH = 8
const OUTLINE_WIDTH = 11
const TILE_RADIUS = 12
const ICO_SIZES = [16, 32, 48]
const APPLE_TOUCH_SIZE = 180

// Below ~24px an outline adds under 2px per side, so it stops reading as an
// outline and just muddies the letterforms.
const OUTLINE_MIN_SIZE = 24

// `square` means the apple-touch icon. iOS masks and rounds it itself, so
// rounding here would show as a fringe inside the system's own corner radius.
const treatmentFor = (size, square) => ({
  outline: Boolean(VARIANT.outline) && size >= OUTLINE_MIN_SIZE,
  tile: square ? APPLE_TOUCH_TILE : VARIANT.tile,
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
  const { outline, tile, radius } = treatmentFor(size, square)

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" ` +
    `width="${size}" height="${size}">` +
    (tile ? `<rect width="64" height="64" rx="${radius}" fill="${tile}"/>` : '') +
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

// Chrome can hang instead of exiting, and the sync spawn helpers default to a
// timeout of 0 — wait forever. That combination stalled a ~1s rasterise for 30
// minutes of CI (#1203) with no output and nothing to act on. 60s against an
// observed ~1s is generous enough that a loaded runner never trips it.
const RASTERIZE_TIMEOUT_MS = 60_000
const RASTERIZE_ATTEMPTS = 2

// `timeout`'s killSignal reaches only the process we spawned, so a killed Chrome
// leaves its renderer and zygote children running — measured: one orphan per
// attempt. `detached` makes Chrome a process-group leader so the whole group can be
// reaped by signalling -pid.
//
// The signal-0 probe first is what makes that safe: if a future Node ignored
// `detached`, the child would sit in our own group, the probe would raise ESRCH, and
// we would skip rather than signal a group we do not own.
function reapGroup(pid) {
  if (!pid) return

  try {
    process.kill(-pid, 0)
  } catch {
    return // ESRCH — no group of ours to reap, which is the normal exit path.
  }

  try {
    process.kill(-pid, 'SIGKILL')
  } catch {
    // Raced with the group exiting on its own. Nothing left to do.
  }
}

function runChrome(chrome, { page, out, size }) {
  const result = spawnSync(
    chrome,
    [
      '--headless=new',
      // Ubuntu 23.10+ sets apparmor_restrict_unprivileged_userns=1, so Chrome's
      // namespace sandbox cannot start on the CI image. Opt-in rather than
      // unconditional: local runs keep the sandbox. The only content rendered is
      // a data: URI built by the caller, and the flag does not alter output bytes.
      ...(process.env.CHROME_NO_SANDBOX ? ['--no-sandbox'] : []),
      // Startup work that can block on the network but cannot affect rasterisation —
      // the component updater and background fetches are the best remaining
      // explanation for the #1203 stall, though an unreproducible hang means that
      // stays a hypothesis. The timeout below is the actual guarantee.
      //
      // Notably absent, both tried and rejected:
      //   --user-data-dir  hangs macOS Chrome outright — every location, precreated
      //     or not, sandboxed or not, old headless or new. The default profile is
      //     what works, even alongside a running Chrome.
      //   --virtual-time-budget  the usual headless-screenshot advice, but it lets
      //     Chrome capture before the data: URI <img> decodes, trading a loud hang
      //     for a silently blank icon.
      '--disable-extensions',
      '--disable-background-networking',
      '--disable-component-update',
      '--disable-crash-reporter',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--default-background-color=00000000',
      `--screenshot=${out}`,
      `--window-size=${size},${size}`,
      page
    ],
    // SIGKILL, not the default SIGTERM: a wedged Chrome may never service a polite
    // signal, and the whole point of the timeout is a bounded exit.
    {
      stdio: 'ignore',
      timeout: RASTERIZE_TIMEOUT_MS,
      killSignal: 'SIGKILL',
      detached: true // see reapGroup above
    }
  )

  // spawnSync reports rather than throws, so both failure shapes are handled here:
  // `error` for the timeout, a non-zero `status` for a Chrome that exited badly.
  if (result.error || result.status !== 0) {
    reapGroup(result.pid)

    throw (
      result.error ??
      new Error(
        `Chrome exited ${result.signal ? `on ${result.signal}` : `with status ${result.status}`} rasterising ${size}px`
      )
    )
  }
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

  for (let attempt = 1; attempt <= RASTERIZE_ATTEMPTS; attempt++) {
    // A timed-out Chrome can leave a partial screenshot behind, and --screenshot
    // does not truncate what it cannot finish writing.
    fs.rmSync(out, { force: true })

    try {
      runChrome(chrome, { page, out, size })
      break
    } catch (error) {
      if (attempt === RASTERIZE_ATTEMPTS) {
        throw new Error(
          `Chrome failed to rasterise ${size}px after ${RASTERIZE_ATTEMPTS} attempts: ${error.message}`
        )
      }
      // stderr, because stdout is the artifact listing this script emits.
      console.error(
        `  ! ${size}px rasterise failed (attempt ${attempt}/${RASTERIZE_ATTEMPTS}), retrying: ${error.message}`
      )
    }
  }

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
