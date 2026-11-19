import "./styles/theme.css";
import { siteConfig } from "./data/site";

document.documentElement.style.setProperty("--accent", siteConfig.accent);

const savedTheme = localStorage.getItem("amfi-theme") || "dark";
document.documentElement.setAttribute("data-theme", savedTheme);

const escapeHtml = (str: string): string =>
  str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

const app = document.getElementById("app")!;
app.innerHTML = `
  <header class="nav">
    <div class="container nav-inner">
      <a class="brand" href="#">
        <img src="./favicon.png" alt="${escapeHtml(siteConfig.title)} icon" />
        <span>${escapeHtml(siteConfig.title)}</span>
      </a>
      <nav class="nav-links">
        <a href="#features">Features</a>
        <a href="#how-it-works">How It Works</a>
        <a href="#quick-start">Quick Start</a>
        <a href="${siteConfig.repoUrl}" target="_blank" rel="noreferrer">GitHub</a>
      </nav>
      <button class="theme-btn" id="theme-toggle" type="button">
        ${savedTheme === "dark" ? "Light Mode" : "Dark Mode"}
      </button>
    </div>
  </header>

  <main class="container">
    <section class="hero" style="border-top: none;">
      <img class="hero-icon" src="./icon-512.png" alt="${escapeHtml(siteConfig.title)} app icon" />
      <div><span class="badge">${escapeHtml(siteConfig.category)}</span></div>
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
  </main>

  <footer>
    <div class="container footer-inner">
      <span>AMFI-Disable · Local-First Software</span>
      <div class="footer-links">
        <a href="https://amfi-disable.github.io/" target="_blank" rel="noreferrer">All Projects</a>
        <a href="${siteConfig.repoUrl}" target="_blank" rel="noreferrer">Repository</a>
        <a href="${siteConfig.repoUrl}/blob/main/changelog.md" target="_blank" rel="noreferrer">Changelog</a>
        <a href="${siteConfig.repoUrl}/blob/main/license" target="_blank" rel="noreferrer">MIT License</a>
      </div>
    </div>
  </footer>
`;

const themeBtn = document.getElementById("theme-toggle") as HTMLButtonElement;
themeBtn.addEventListener("click", () => {
  const next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", next);
  localStorage.setItem("amfi-theme", next);
  themeBtn.textContent = next === "dark" ? "Light Mode" : "Dark Mode";
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
