import type { EngineInterface, Register } from 'claude-code'

// A live context-window reading above the chat input on the remote surfaces:
// the VS Code panel (`vscode`), desktop and mobile. The terminal is left alone
// because ~/.claude/statusline.sh already draws its own bar there.
//
// This is the durable replacement for the cc-panel-context patch: a mod is
// loaded by the engine, not written into the extension's webview bundle, so an
// extension update cannot erase it.
//
// The reading comes from $.session.usage() — the engine's own status-line
// figures — so it stays correct under a proxy alias, where the panel's built-in
// indicator (which looks the window up by model name in the transcript) reads 0.
//
// Placement note: on engine 2.1.314 the `AbovePrompt` band is raised on the
// `terminal` and `desktop` surfaces only (RENDER_SURFACES_OF:
// `AbovePrompt:["terminal","desktop"], Pane:<all>`). The `vscode` surface draws
// its status lines in the same above-input container as that band, directly
// above the composer (webview/index.js: `data-engine-status`), so $.ui.status
// is the supported placement above the VS Code chat input.

const BAR_CELLS = 10
const TICK_MS = 1500

let shown = ''
let busy = false

function compact(n: number): string {
  if (n >= 1_000_000) {
    const millions = n / 1_000_000
    return `${Number.isInteger(millions) ? millions : millions.toFixed(1)}M`
  }
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`
  return String(n)
}

function lineFor(
  tokens: number | undefined,
  window: number,
  percent: number | undefined,
): string {
  // usage() leaves tokens and percent out until the first API response of the
  // live window (a fresh or just-compacted session). Say "—" then; a 0% would
  // be a reading the engine never gave.
  const pct =
    typeof percent === 'number' && Number.isFinite(percent)
      ? percent
      : typeof tokens === 'number' && window > 0
        ? (tokens / window) * 100
        : undefined

  const filled =
    pct === undefined
      ? 0
      : Math.round((Math.min(Math.max(pct, 0), 100) / 100) * BAR_CELLS)
  const bar = '█'.repeat(filled) + '░'.repeat(BAR_CELLS - filled)
  const windowText = window > 0 ? compact(window) : '?'

  if (pct === undefined || tokens === undefined) {
    return `ctx ${bar} — · ${windowText} window`
  }
  return `ctx ${bar} ${Math.round(Math.max(pct, 0))}% · ${compact(tokens)}/${windowText}`
}

async function refresh($: EngineInterface): Promise<void> {
  if (busy) return
  busy = true
  try {
    // Draw only where no terminal statusline does: a remote surface (the VS Code
    // panel, desktop, mobile). An empty list is a -p run or nothing attached yet.
    const surfaces = await $.session.surfaces()
    if (!surfaces.some(surface => surface !== 'terminal')) {
      if (shown !== '') {
        shown = ''
        $.ui.status(undefined)
      }
      return
    }

    const { context } = await $.session.usage()
    const text = lineFor(context.tokens, context.window, context.percent)
    if (text !== shown) {
      shown = text
      $.ui.status(text)
    }
  } catch {
    // No reading this tick: keep the last line rather than claim a zero.
  } finally {
    busy = false
  }
}

export const register: Register = on => {
  let stop: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    stop?.cancel()
    stop = $.clock.every(TICK_MS, () => {
      void refresh($)
    })
    await refresh($)
    return started
  })

  on('turn.complete', async ($, e, next) => {
    const ended = await next(e)
    await refresh($)
    return ended
  })

  // A client that has just attached has never seen the line: a webview reload
  // or a reopened window starts a fresh client, and the timer's send-only-on-
  // change guard would otherwise stay quiet until the number moves.
  on('session.attach', async ($, e, next) => {
    const attached = await next(e)
    shown = ''
    await refresh($)
    return attached
  })

  on('session.end', ($, e, next) => {
    stop?.cancel()
    stop = undefined
    shown = ''
    $.ui.status(undefined)
    return next(e)
  })
}
