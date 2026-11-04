// proton-iframe-scan.js
// Self-contained Proton mail iframe scanner injected via chrome.scripting on Chromium.
//
// Flow: service worker injects this function into Proton's sandboxed content iframe → returns link/body flags.

/** @returns {Array<{ id: string, detail?: string }>} */
export function scanProtonIframeDocument() {
  const MICROSOFT_FAMILY = [
    "microsoft.com",
    "live.com",
    "hotmail.com",
    "outlook.com",
    "office.com",
    "office365.com",
    "microsoftonline.com",
  ];

  const URL_SHORTENER_DOMAINS = new Set([
    "bit.ly",
    "t.co",
    "goo.gl",
    "tinyurl.com",
    "ow.ly",
    "is.gd",
    "buff.ly",
    "rebrand.ly",
    "short.link",
    "lnkd.in",
    "rb.gy",
    "cutt.ly",
    "tiny.cc",
    "soo.gd",
    "s.id",
    "shorturl.at",
    "bl.ink",
  ]);

  const SUSPICIOUS_TLDS = new Set([
    "zip",
    "mov",
    "top",
    "click",
    "xyz",
    "shop",
    "monster",
    "bond",
    "rest",
    "gq",
    "ml",
    "cf",
    "tk",
    "work",
    "kim",
    "cam",
    "quest",
    "sbs",
  ]);

  const root = document.getElementById("proton-root");
  if (!(root instanceof HTMLElement) || root.textContent.trim().length === 0) {
    return [];
  }

  /** @type {Array<{ id: string, detail?: string }>} */
  const flags = [];
  const seen = new Set();

  const registrableDomain = (hostname) => {
    const parts = String(hostname ?? "").replace(/^www\./, "").toLowerCase().split(".").filter(Boolean);
    if (parts.length <= 2) {
      return parts.join(".");
    }
    return parts.slice(-2).join(".");
  };

  const bodyText = String(root.innerText ?? "")
    .replace(/[\w.+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi, " ");
  const brandPhrases = [
    /microsoft\s+(account|365|office|corporation)/i,
    /office\s*365/i,
    /sign in to your microsoft/i,
    /windows live/i,
    /microsoft account team/i,
    /outlook team/i,
  ];
  const impersonatesMicrosoft = brandPhrases.some((pattern) => pattern.test(bodyText))
    || [...root.querySelectorAll("img")].some((img) => {
      if (!(img instanceof HTMLImageElement)) {
        return false;
      }
      const alt = (img.alt ?? "").toLowerCase();
      const src = (img.src ?? "").toLowerCase();
      return alt.includes("microsoft") || src.includes("microsoft");
    });

  const shouldSkipBrandHost = (host) => {
    const normalized = String(host ?? "").replace(/^www\./, "").toLowerCase();
    if (!normalized) {
      return true;
    }
    if (normalized.endsWith(".proton.me") || normalized.endsWith(".protonmail.com")) {
      return true;
    }
    return false;
  };

  root.querySelectorAll("a[href]").forEach((anchor) => {
    if (!(anchor instanceof HTMLAnchorElement)) {
      return;
    }

    let url;
    try {
      url = new URL(anchor.href);
    } catch {
      return;
    }

    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return;
    }

    const host = url.hostname.replace(/^www\./, "");

    if (url.protocol === "http:") {
      const key = `insecure-http:${url.href}`;
      if (!seen.has(key)) {
        seen.add(key);
        flags.push({ id: "insecure-http", detail: url.href });
      }
    }

    if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(url.hostname)) {
      const key = `ip-address:${url.hostname}`;
      if (!seen.has(key)) {
        seen.add(key);
        flags.push({ id: "ip-address", detail: url.hostname });
      }
    }

    if (/xn--/i.test(url.hostname)) {
      const key = `homograph-link:${url.hostname}`;
      if (!seen.has(key)) {
        seen.add(key);
        flags.push({ id: "homograph-link", detail: url.hostname });
      }
    }

    const shortenerHost = registrableDomain(host);
    if (URL_SHORTENER_DOMAINS.has(host) || URL_SHORTENER_DOMAINS.has(shortenerHost)) {
      const key = `url-shortener:${host}`;
      if (!seen.has(key)) {
        seen.add(key);
        flags.push({ id: "url-shortener", detail: host });
      }
    }

    const tld = host.split(".").pop()?.toLowerCase() ?? "";
    if (SUSPICIOUS_TLDS.has(tld)) {
      const key = `suspicious-tld:${host}`;
      if (!seen.has(key)) {
        seen.add(key);
        flags.push({ id: "suspicious-tld", detail: host });
      }
    }

    if (/\/wp-admin|wp-login\.php/i.test(url.pathname)) {
      const key = `suspicious-admin-path:${url.href}`;
      if (!seen.has(key)) {
        seen.add(key);
        flags.push({ id: "suspicious-admin-path", detail: url.href });
      }
    }

    if (impersonatesMicrosoft) {
      const onMicrosoftFamily = MICROSOFT_FAMILY.some(
        (domain) => host === domain || host.endsWith(`.${domain}`)
      );
      if (!onMicrosoftFamily && !shouldSkipBrandHost(host)) {
        const key = `brand-impersonation:microsoft→${host}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "brand-impersonation", detail: `Microsoft branding → ${host}` });
        }
      }
    }

    const label = anchor.textContent.trim();
    const labelDomain = label.match(/(?:https?:\/\/)?(?:www\.)?([a-z0-9-]+(?:\.[a-z0-9-]+)+)/i)?.[1];
    if (labelDomain) {
      const normalizedLabel = labelDomain.replace(/^www\./, "");
      if (host && normalizedLabel && !host.endsWith(normalizedLabel) && !normalizedLabel.endsWith(host)) {
        const key = `mismatched-destination:${labelDomain}->${host}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "mismatched-destination", detail: `${labelDomain} → ${host}` });
        }
      }
    }
  });

  return flags;
}
