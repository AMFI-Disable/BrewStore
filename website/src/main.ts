import "./styles/theme.css";
import { siteConfig } from "./data/site";

document.documentElement.style.setProperty("--accent", siteConfig.accent);

const colorSchemeMedia = window.matchMedia("(prefers-color-scheme: dark)");

function resolveInitialTheme(): "dark" | "light" {
  const saved = localStorage.getItem("amfi-theme");
  if (saved === "dark" || saved === "light") return saved;
  return colorSchemeMedia.matches ? "dark" : "light";
}

const repoSlug = siteConfig.repoUrl.replace(/^https?:\/\/github\.com\//, "");

function updateThemedGraphs(theme: "dark" | "light"): void {
  const starImg = document.getElementById("star-history-img") as HTMLImageElement | null;
  if (starImg) {
    const themeParam = theme === "dark" ? "&theme=dark" : "";
    starImg.src = `https://api.star-history.com/svg?repos=${repoSlug}&type=Date${themeParam}`;
  }
}

function applyTheme(theme: "dark" | "light", persist = false): void {
  document.documentElement.setAttribute("data-theme", theme);
  const metaTheme = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
  if (metaTheme) {
    metaTheme.content = theme === "dark" ? "#0B0E14" : "#F6F8FA";
  }
  const btn = document.getElementById("theme-toggle");
  if (btn) {
    btn.textContent = theme === "dark" ? "Light Mode" : "Dark Mode";
  }
  if (persist) {
    localStorage.setItem("amfi-theme", theme);
  }
  updateThemedGraphs(theme);
}

function syncDisplayContext(): void {
  const root = document.documentElement;
  const w = window.innerWidth;
  root.setAttribute("data-viewport", w < 640 ? "mobile" : w < 1024 ? "tablet" : "desktop");
  root.setAttribute("data-dpr", window.devicePixelRatio >= 2 ? "hidpi" : "standard");
  root.setAttribute("data-pointer", window.matchMedia("(pointer: coarse)").matches ? "coarse" : "fine");
  const ua = navigator.userAgent.toLowerCase();
  const os = ua.includes("mac") ? "macos" : ua.includes("win") ? "windows" : ua.includes("linux") ? "linux" : "other";
  root.setAttribute("data-os", os);
}

applyTheme(resolveInitialTheme());
syncDisplayContext();
window.addEventListener("resize", syncDisplayContext, { passive: true });
colorSchemeMedia.addEventListener("change", (e) => {
  if (!localStorage.getItem("amfi-theme")) {
    applyTheme(e.matches ? "dark" : "light");
  }
});

const escapeHtml = (str: string): string =>
  str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

let activeTabIdx = 0;

const initialTheme = document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
const app = document.getElementById("app")!;
app.innerHTML = `
  <header class="nav">
    <div class="container nav-inner">
      <a class="brand" href="#">
        <img src="./favicon.png" alt="${escapeHtml(siteConfig.title)} icon" />
        <span>${escapeHtml(siteConfig.title)}</span>
      </a>
      <nav class="nav-links">
        <a href="#preview">Interactive</a>
        <a href="#features">Features</a>
        <a href="#how-it-works">How It Works</a>
        <a href="#quick-start">Quick Start</a>
        <a href="https://amfi-disable.github.io/#arcade">Arcade</a>
      </nav>
      <div class="nav-actions">
        <a class="hub-pill" href="https://amfi-disable.github.io/#${escapeHtml(siteConfig.hubHash)}" title="Open ${escapeHtml(siteConfig.hubName)}">${escapeHtml(siteConfig.hubName)}</a>
        <a class="nav-home" href="https://amfi-disable.github.io/" title="Back to AMFI Plaza">&larr; Plaza</a>
        <button class="theme-btn" id="theme-toggle" type="button">
          ${initialTheme === "dark" ? "Light Mode" : "Dark Mode"}
        </button>
      </div>
    </div>
  </header>

  <main class="container">
    <section class="hero" style="border-top: none;">
      <img class="hero-icon" src="./icon-512.png" alt="${escapeHtml(siteConfig.title)} app icon" />
      <div><span class="badge">${escapeHtml(siteConfig.hubName)} · ${escapeHtml(siteConfig.category)}</span></div>
      <h1>${escapeHtml(siteConfig.title)}</h1>
      <p>${escapeHtml(siteConfig.tagline)}</p>
      <div class="cta-row">
        <a class="btn btn-primary" href="${siteConfig.primaryCta.href}">${escapeHtml(siteConfig.primaryCta.label)}</a>
        <a class="btn btn-secondary" href="${siteConfig.secondaryCta.href}" target="_blank" rel="noreferrer">${escapeHtml(siteConfig.secondaryCta.label)}</a>
      </div>
      <div class="cmd-pill">
        <code>${escapeHtml(siteConfig.quickCmd)}</code>
        <button class="copy-btn" data-copy="${escapeHtml(siteConfig.quickCmd)}" type="button">Copy</button>
      </div>
    </section>

    <section id="preview">
      <h2 class="section-title">Interactive Walkthrough</h2>
      <p class="section-sub">Explore ${escapeHtml(siteConfig.title)} capabilities inside ${escapeHtml(siteConfig.hubName)}.</p>
      <div class="preview-box">
        <div class="preview-tabs" id="preview-tabs">
          ${siteConfig.previewTabs
            .map(
              (t, idx) =>
                `<button class="preview-tab ${idx === 0 ? "active" : ""}" data-tab-idx="${idx}" type="button">${escapeHtml(t.tab)}</button>`
            )
            .join("")}
        </div>
        <div class="preview-panel" id="preview-panel">
          <h3>${escapeHtml(siteConfig.previewTabs[0].title)}</h3>
          <p>${escapeHtml(siteConfig.previewTabs[0].body)}</p>
        </div>
      </div>
    </section>

    <section id="features">
      <h2 class="section-title">Core Features</h2>
      <p class="section-sub">Engineered for speed, local-first privacy, and clean daily workflows.</p>
      <div class="grid">
        ${siteConfig.features
          .map(
            (f) => `
          <article class="card">
            <h3>${escapeHtml(f.title)}</h3>
            <p>${escapeHtml(f.desc)}</p>
          </article>`
          )
          .join("")}
      </div>
    </section>

    <section id="how-it-works">
      <h2 class="section-title">How It Works</h2>
      <p class="section-sub">A transparent, deterministic pipeline from input to execution.</p>
      <div class="grid">
        ${siteConfig.steps
          .map(
            (s, idx) => `
          <article class="card">
            <div class="step-num">0${idx + 1}</div>
            <h3>${escapeHtml(s.title)}</h3>
            <p>${escapeHtml(s.desc)}</p>
          </article>`
          )
          .join("")}
      </div>
    </section>

    <section id="quick-start">
      <h2 class="section-title">Quick Start &amp; Safety</h2>
      <p class="section-sub">Local-first, zero telemetry, and open source under the MIT License.</p>
      <div class="install-list">
        ${siteConfig.installCmds
          .map(
            (item) => `
          <div class="install-item">
            <div class="install-label">${escapeHtml(item.label)}</div>
            <div class="install-code">
              <code>${escapeHtml(item.cmd)}</code>
              <button class="copy-btn" data-copy="${escapeHtml(item.cmd)}" type="button">Copy</button>
            </div>
          </div>`
          )
          .join("")}
      </div>
      <ul class="req-list">
        ${siteConfig.requirements.map((r) => `<li>${escapeHtml(r)}</li>`).join("")}
      </ul>
    </section>

    <section id="github-stats">
      <h2 class="section-title">Star History</h2>
      <p class="section-sub">GitHub star growth for ${escapeHtml(siteConfig.title)}.</p>
      <article class="graph-card">
        <a href="https://www.star-history.com/#${escapeHtml(repoSlug)}&Date" target="_blank" rel="noreferrer">
          <img id="star-history-img" alt="${escapeHtml(siteConfig.title)} Star History Chart" loading="lazy" />
        </a>
      </article>
    </section>
  </main>

  <footer>
    <div class="container footer-inner">
      <span>AMFI-Disable · ${escapeHtml(siteConfig.hubName)}</span>
      <div class="footer-links">
        <a href="https://amfi-disable.github.io/">AMFI Plaza</a>
        <a href="https://amfi-disable.github.io/#${escapeHtml(siteConfig.hubHash)}">${escapeHtml(siteConfig.hubName)}</a>
        <a href="https://amfi-disable.github.io/#arcade">AMFI Arcade</a>
        <a href="${siteConfig.repoUrl}" target="_blank" rel="noreferrer">Repository</a>
        <a href="${siteConfig.repoUrl}/blob/main/license" target="_blank" rel="noreferrer">MIT License</a>
      </div>
    </div>
  </footer>
`;

updateThemedGraphs(initialTheme);

const themeBtn = document.getElementById("theme-toggle") as HTMLButtonElement;
themeBtn.addEventListener("click", () => {
  const next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
  applyTheme(next, true);
});

document.getElementById("preview-tabs")?.addEventListener("click", (e) => {
  const btn = (e.target as HTMLElement).closest<HTMLButtonElement>("[data-tab-idx]");
  if (!btn) return;
  const idx = Number(btn.dataset.tabIdx);
  const tab = siteConfig.previewTabs[idx];
  if (!tab || idx === activeTabIdx) return;
  activeTabIdx = idx;
  document.querySelectorAll(".preview-tab").forEach((el, i) => {
    el.classList.toggle("active", i === idx);
  });
  const panel = document.getElementById("preview-panel");
  if (panel) {
    panel.innerHTML = `<h3>${escapeHtml(tab.title)}</h3><p>${escapeHtml(tab.body)}</p>`;
  }
});

document.querySelectorAll<HTMLButtonElement>(".copy-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const text = btn.dataset.copy || "";
    try {
      await navigator.clipboard.writeText(text);
      const prev = btn.textContent;
      btn.textContent = "Copied!";
      setTimeout(() => {
        btn.textContent = prev;
      }, 1400);
    } catch {
      btn.textContent = "Failed";
    }
  });
});
