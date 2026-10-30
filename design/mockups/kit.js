// EarBud mockups — shared icon set (SF Symbols-style line icons, drawn for these mockups).
// Usage: <i class="ic" data-i="waveform"></i>. Add data-w="2" to change stroke width.
(function () {
  const S = (d) => `<path d="${d}"/>`;
  const I = {
    waveform: S("M4 10v4M8 6.5v11M12 3.5v17M16 7.5v9M20 10v4"),
    trash: S("M4 7h16M9.5 7V4.5h5V7M6.5 7l.9 12.2a1.5 1.5 0 0 0 1.5 1.3h6.2a1.5 1.5 0 0 0 1.5-1.3L17.5 7M10.2 11v5.5M13.8 11v5.5"),
    history: '<circle cx="12" cy="12" r="8.5"/>' + S("M12 7.5V12l3.2 2"),
    sidebar: '<rect x="3" y="4.5" width="18" height="15" rx="3"/>' + S("M9.5 4.5v15M5.5 8h2M5.5 10.5h2"),
    search: '<circle cx="10.5" cy="10.5" r="6"/>' + S("M15 15l5 5"),
    sync: S("M18.8 9A7.5 7.5 0 0 0 5.4 8.6M5.2 15a7.5 7.5 0 0 0 13.4.4M19 4.5V9h-4.5M5 19.5V15h4.5"),
    play: '<path d="M7.5 4.8v14.4a1 1 0 0 0 1.5.86l12-7.2a1 1 0 0 0 0-1.72l-12-7.2A1 1 0 0 0 7.5 4.8z" fill="currentColor" stroke="none"/>',
    pause: '<rect x="6" y="4.5" width="4.2" height="15" rx="1.2" fill="currentColor" stroke="none"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="1.2" fill="currentColor" stroke="none"/>',
    back15: S("M5 9.5A8 8 0 1 1 4 12M4.5 4.5v5h5") + '<text x="12.4" y="15.4" font-size="7.2" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="-apple-system">15</text>',
    fwd15: S("M19 9.5A8 8 0 1 0 20 12M19.5 4.5v5h-5") + '<text x="11.6" y="15.4" font-size="7.2" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="-apple-system">15</text>',
    more: '<circle cx="12" cy="12" r="9"/><circle cx="8" cy="12" r="1.1" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.1" fill="currentColor" stroke="none"/><circle cx="16" cy="12" r="1.1" fill="currentColor" stroke="none"/>',
    share: S("M12 3.5v11M8.2 7.2 12 3.5l3.8 3.7M8 10.5H6.5A1.5 1.5 0 0 0 5 12v7a1.5 1.5 0 0 0 1.5 1.5h11A1.5 1.5 0 0 0 19 19v-7a1.5 1.5 0 0 0-1.5-1.5H16"),
    copy: '<rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2"/>' + S("M15.5 8.5V5.5A1.5 1.5 0 0 0 14 4H5.5A1.5 1.5 0 0 0 4 5.5V14a1.5 1.5 0 0 0 1.5 1.5h3"),
    folder: S("M3.5 7V17.5A1.5 1.5 0 0 0 5 19h14a1.5 1.5 0 0 0 1.5-1.5v-8.5A1.5 1.5 0 0 0 19 7.5h-7L10 5H5A1.5 1.5 0 0 0 3.5 6.5z"),
    mic: '<rect x="9" y="3" width="6" height="11.5" rx="3"/>' + S("M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"),
    micslash: '<rect x="9" y="3" width="6" height="11.5" rx="3"/>' + S("M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3M4 3.5l16 17"),
    bulb: S("M9.5 18h5M10.3 21h3.4M12 3a6 6 0 0 0-3.6 10.8c.7.5 1.1 1.3 1.1 2.2v.5h5V16c0-.9.4-1.7 1.1-2.2A6 6 0 0 0 12 3z"),
    bell: S("M6 16.5V11a6 6 0 0 1 12 0v5.5l1.6 1.8H4.4zM10 20.5a2 2 0 0 0 4 0"),
    bt: S("M7 7.5l10 9-5 4.5V3l5 4.5-10 9"),
    check: S("M5 12.5l4.5 4.5L19 7.5"),
    checkc: '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M7.5 12.3l3 3 6-6.3" stroke="#fff" stroke-width="2.1"/>',
    warn: '<path d="M10.3 4.2a2 2 0 0 1 3.4 0l8 13.6A2 2 0 0 1 20 20.8H4a2 2 0 0 1-1.7-3L10.3 4.2z" fill="currentColor" stroke="none"/><path d="M12 9v5" stroke="#fff" stroke-width="2.2"/><circle cx="12" cy="17.3" r="1.25" fill="#fff" stroke="none"/>',
    xc: '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="M8.5 8.5l7 7M15.5 8.5l-7 7" stroke="#fff" stroke-width="2"/>',
    x: S("M6 6l12 12M18 6 6 18"),
    chevr: S("M9 5l7 7-7 7"),
    chevd: S("M5 9l7 7 7-7"),
    updown: S("M8 9.5l4-4 4 4M8 14.5l4 4 4-4"),
    retry: S("M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4v4.5H15"),
    buzz: '<rect x="8.5" y="5" width="7" height="14" rx="2"/>' + S("M5.2 9a5 5 0 0 0 0 6M18.8 9a5 5 0 0 1 0 6M2.6 7a8.5 8.5 0 0 0 0 10M21.4 7a8.5 8.5 0 0 1 0 10"),
    down: '<circle cx="12" cy="12" r="9"/>' + S("M12 7.5v8.5M8.3 12.6 12 16.3l3.7-3.7"),
    shield: S("M12 3l7.5 3v5.5c0 4.6-3.1 8-7.5 9.8-4.4-1.8-7.5-5.2-7.5-9.8V6z") + S("M8.8 12.1l2.2 2.2 4.3-4.4"),
    laptop: S("M5 15.5V6.5A1.5 1.5 0 0 1 6.5 5h11A1.5 1.5 0 0 1 19 6.5v9M2.5 18.5h19l-1-2.5h-17z"),
    display: '<rect x="3" y="4" width="18" height="12.5" rx="1.8"/>' + S("M9 20.5h6M12 16.5v4"),
    info: '<circle cx="12" cy="12" r="9"/>' + S("M12 11v5.5") + '<circle cx="12" cy="7.8" r="1.1" fill="currentColor" stroke="none"/>',
    doc: S("M7 3.5h6.5l4.5 4.5v11A1.5 1.5 0 0 1 16.5 20.5h-9.5A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5zM13.5 3.5V8H18M8.5 12h7M8.5 15.5h5"),
    pod: '<rect x="7" y="6" width="10" height="12" rx="3.2"/>' + S("M2.5 9.5h4.5M2.5 14.5h4.5M17 9.5h4.5M17 14.5h4.5") + '<circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/>',
    rec: '<circle cx="12" cy="12" r="7" fill="currentColor" stroke="none"/>',
    stop: '<rect x="6.5" y="6.5" width="11" height="11" rx="2.2" fill="currentColor" stroke="none"/>',
    power: S("M12 3.5v8M7.2 6.5a7 7 0 1 0 9.6 0"),
    gear: '<circle cx="12" cy="12" r="3"/>' + S("M12 2.8v2.6M12 18.6v2.6M21.2 12h-2.6M5.4 12H2.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8M18.5 18.5l-1.8-1.8M7.3 7.3 5.5 5.5") + '<circle cx="12" cy="12" r="6.3"/>',
    open: '<rect x="3.5" y="5" width="17" height="14" rx="2"/>' + S("M3.5 9h17"),
    moon: S("M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"),
    lock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/>' + S("M8 10.5V7.5a4 4 0 0 1 8 0v3"),
    wifi: S("M3 9a13 13 0 0 1 18 0M6 12.4a8.5 8.5 0 0 1 12 0M9 15.8a4 4 0 0 1 6 0") + '<circle cx="12" cy="19" r="1.2" fill="currentColor" stroke="none"/>',
    cc: '<rect x="3.5" y="6" width="17" height="12" rx="6"/><circle cx="9.5" cy="12" r="3" fill="currentColor" stroke="none"/>',
    hand: S("M9 11V5.2a1.6 1.6 0 0 1 3.2 0V11M12.2 10V8.4a1.6 1.6 0 0 1 3.2 0V11M15.4 10.6a1.6 1.6 0 0 1 3.2 0V14c0 4-2.6 7-6.6 7-2.6 0-4-1.1-5.3-3L4 13.6a1.6 1.6 0 0 1 2.6-1.8L9 14.4"),
    sparkle: S("M12 3v4M12 17v4M3 12h4M17 12h4"),
    plug: S("M9 3v4.5M15 3v4.5M6.5 7.5h11V11a5.5 5.5 0 0 1-11 0zM12 16.5V21"),
    signal: '<rect x="4" y="14" width="3" height="5" rx="1" fill="currentColor" stroke="none"/><rect x="10.5" y="10" width="3" height="9" rx="1" fill="currentColor" stroke="none"/><rect x="17" y="6" width="3" height="13" rx="1" fill="currentColor" stroke="none" opacity=".25"/>',
    signal3: '<rect x="4" y="14" width="3" height="5" rx="1" fill="currentColor" stroke="none"/><rect x="10.5" y="10" width="3" height="9" rx="1" fill="currentColor" stroke="none"/><rect x="17" y="6" width="3" height="13" rx="1" fill="currentColor" stroke="none"/>',
    signal1: '<rect x="4" y="14" width="3" height="5" rx="1" fill="currentColor" stroke="none"/><rect x="10.5" y="10" width="3" height="9" rx="1" fill="currentColor" stroke="none" opacity=".25"/><rect x="17" y="6" width="3" height="13" rx="1" fill="currentColor" stroke="none" opacity=".25"/>',
    // menu-bar glyph for EarBud: a small speech bud with three bars (matches icon concept A)
    bud: '<path d="M12 3.2a8.3 8.3 0 1 1-4.6 15.2L3.6 20.2l1.3-3.9A8.3 8.3 0 0 1 12 3.2z"/>' + S("M9 10v4M12 8.3v7.4M15 10v4"),
    budsync: '<path d="M12 3.2a8.3 8.3 0 1 1-4.6 15.2L3.6 20.2l1.3-3.9A8.3 8.3 0 0 1 12 3.2z"/>' + S("M15.4 10.3a3.6 3.6 0 0 0-6.6.3M8.6 13.7a3.6 3.6 0 0 0 6.6-.3M15.6 8.4v2h-2M8.4 15.6v-2h2")
  };
  const apple = '<svg viewBox="0 0 17 20"><path fill="currentColor" d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9-.1 0-2.7-1-2.7-4.1zM11.6 3c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.1.1 2.3-.6 3-1.5z"/></svg>';
  window.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".ic[data-i]").forEach((el) => {
      const k = el.getAttribute("data-i");
      if (k === "apple") { el.innerHTML = apple; return; }
      const w = el.getAttribute("data-w") || "1.7";
      el.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${I[k] || ""}</svg>`;
    });
    document.querySelectorAll(".tl").forEach((el) => { if (!el.children.length) el.innerHTML = "<i></i><i></i><i></i>"; });
    // Generic wristband recorder drawing (not Field Labs artwork):
    // <div class="fieldy-art" data-w="220" data-led="#3BD36B" data-tap="1" data-ring="0.6" data-radar="1" data-badge="check|warn"></div>
    document.querySelectorAll(".fieldy-art").forEach((el, n) => {
      const d = el.dataset, w = +(d.w || 220), led = d.led, id = "f" + n;
      let s = `<svg viewBox="0 0 220 160" width="${w}" height="${w * 160 / 220}" style="overflow:visible">
        <defs>
          <linearGradient id="${id}b" x1="0" x2="1"><stop offset="0" stop-color="#CFC6BA" stop-opacity="0"/><stop offset=".22" stop-color="#CFC6BA"/><stop offset=".78" stop-color="#CFC6BA"/><stop offset="1" stop-color="#CFC6BA" stop-opacity="0"/></linearGradient>
          <linearGradient id="${id}p" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4A4B4F"/><stop offset="1" stop-color="#232427"/></linearGradient>
          <radialGradient id="${id}g"><stop offset="0" stop-color="${led || "#fff"}" stop-opacity=".9"/><stop offset="1" stop-color="${led || "#fff"}" stop-opacity="0"/></radialGradient>
          <filter id="${id}s" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="6" stdDeviation="7" flood-color="#2a1a0a" flood-opacity=".28"/></filter>
        </defs>`;
      if (d.radar) s += `<g fill="none" stroke="#2C7A6B"><circle cx="110" cy="80" r="68" stroke-opacity=".24" stroke-width="1.5"/><circle cx="110" cy="80" r="84" stroke-opacity=".14" stroke-width="1.5"/><circle cx="110" cy="80" r="100" stroke-opacity=".07" stroke-width="1.5"/></g>`;
      s += `<rect x="0" y="58" width="220" height="44" rx="10" fill="url(#${id}b)"/>
        <g stroke="#B8AEA1" stroke-opacity=".5" stroke-width="1"><path d="M22 66h40M22 94h40M158 66h40M158 94h40"/></g>
        <rect x="62" y="32" width="96" height="96" rx="30" fill="url(#${id}p)" filter="url(#${id}s)"/>
        <rect x="63" y="33" width="94" height="94" rx="29" fill="none" stroke="#fff" stroke-opacity=".1"/>
        <circle cx="110" cy="84" r="19" fill="#2B2C2F" stroke="#fff" stroke-opacity=".12" stroke-width="1.5"/>
        <circle cx="110" cy="84" r="13" fill="none" stroke="#000" stroke-opacity=".25"/>`;
      if (led) s += `<circle cx="110" cy="50" r="12" fill="url(#${id}g)"/><circle cx="110" cy="50" r="3.6" fill="${led}"/>`;
      else s += `<circle cx="110" cy="50" r="3.2" fill="#55565A"/>`;
      if (d.tap) s += `<g fill="none" stroke="#2C7A6B" stroke-width="2.2"><circle cx="110" cy="84" r="25" stroke-opacity=".9"/><circle cx="110" cy="84" r="33" stroke-opacity=".45"/></g>`;
      if (d.ring) { const c = 2 * Math.PI * 64, p = +d.ring; s += `<circle cx="110" cy="80" r="64" fill="none" stroke="#2C7A6B" stroke-opacity=".15" stroke-width="5"/><circle cx="110" cy="80" r="64" fill="none" stroke="#2C7A6B" stroke-width="5" stroke-linecap="round" stroke-dasharray="${c * p} ${c}" transform="rotate(-90 110 80)"/>`; }
      if (d.badge === "check") s += `<circle cx="154" cy="38" r="17" fill="#2FA84F" stroke="#fff" stroke-width="3"/><path d="M146.5 38.5l5 5 9-9.5" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>`;
      if (d.badge === "warn") s += `<circle cx="154" cy="38" r="17" fill="#E8912D" stroke="#fff" stroke-width="3"/><path d="M154 30v10" stroke="#fff" stroke-width="3.2" stroke-linecap="round"/><circle cx="154" cy="46" r="2" fill="#fff"/>`;
      el.innerHTML = s + "</svg>";
    });
    // Waveform scrubbers: <div class="wave" data-n="90" data-at="0.15" data-seed="3">
    document.querySelectorAll(".wave[data-n]").forEach((el) => {
      const n = +el.dataset.n, at = +el.dataset.at, seed = +(el.dataset.seed || 1);
      let h = "";
      for (let i = 0; i < n; i++) {
        const v = Math.abs(Math.sin(i * 0.37 * seed + seed) * 0.55 + Math.sin(i * 1.13 + seed * 2) * 0.3 + Math.sin(i * 0.09) * 0.25);
        const pct = Math.max(10, Math.min(100, Math.round(18 + v * 90)));
        h += `<i class="${i / n < at ? "on" : ""}" style="height:${pct}%"></i>`;
      }
      h += `<span class="head" style="left:${at * 100}%"></span>`;
      el.innerHTML = h;
    });
  });
})();
