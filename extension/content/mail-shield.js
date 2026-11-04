// mail-shield.js
// Local phishing/scam heuristics for webmail — no paid APIs (Mail Shield v1).
//
// Flow: read toggle → find open message → scan DOM → show glass warning banner.

(() => {
  const STORAGE_KEY = "keystrokeauth.mailShieldEnabled";
  const TRUSTED_DOMAINS_KEY = "keystrokeauth.mailShieldTrustedDomains";
  if (window.__dynamicKeyMailShieldLoaded) {
    return;
  }
  window.__dynamicKeyMailShieldLoaded = true;

  const browserAPI = globalThis.browser ?? globalThis.chrome;
  const EXTENSION_ICON_URL = browserAPI.runtime.getURL("icons/icon32.png");
  const SHIELD_BUILD_VERSION = browserAPI.runtime.getManifest?.()?.version ?? "dev";

  /** True when the content script can still talk to the extension background worker. */
  function isExtensionContextValid() {
    try {
      return Boolean(browserAPI.runtime?.id);
    } catch {
      return false;
    }
  }

  /** Sends a runtime message without throwing after an extension reload. */
  function safeRuntimeSendMessage(message, callback) {
    if (!isExtensionContextValid()) {
      if (typeof callback === "function") {
        callback(undefined);
      }
      return;
    }

    try {
      browserAPI.runtime.sendMessage(message, (...args) => {
        void browserAPI.runtime.lastError;
        if (typeof callback === "function") {
          callback(...args);
        }
      });
    } catch {
      if (typeof callback === "function") {
        callback(undefined);
      }
    }
  }

  let mailShieldEnabled = true;
  let scanTimer = null;
  const linkHoverHosts = new Set();
  let trustedDomains = [];
  let dismissedMessageId = null;
  let loggedWarningMessageIds = new Set();
  /** Keeps the last warning visible when Proton re-renders and a rescan briefly finds nothing. */
  let activeWarningState = null;
  let scanGeneration = 0;

  const FLAG_COPY = {
    "mismatch-return": "Mismatch Return — technical reply address may differ from the display name",
    "missing-profile-icon": "Missing Profile Icon — no official verified brand logo beside the sender",
    "provider-warning": "Provider Warning — your email system flagged this message",
    "mismatched-destination": "Mismatched Destination — link target does not match the visible text",
    "insecure-http": "Insecure HTTP — link uses http:// instead of https:// (common in marketing mail)",
    "ip-address": "IP Address Link — link uses raw numbers instead of a domain name",
    "urgent-timer": "Urgent Timer — countdown or high-pressure urgency detected",
    "blurry-graphics": "Blurry Graphics — stretched or low-resolution images detected",
    "broken-layout": "Broken Layout — broken or missing images in the message",
    "fake-unsubscribe": "Fake Unsubscribe — unsubscribe link may lead to a login trap",
    "double-extension": "Double Extension — dangerous file type hidden in the attachment name",
    "generic-attachment-icon": "Generic Attachment — file icon does not match a known document type",
    "homograph-link": "Homograph Link — link domain uses punycode or look-alike characters",
    "brand-impersonation": "Brand Impersonation — message looks like a major brand but links go elsewhere",
    "cta-domain-mismatch": "Suspicious Button Link — action button leads to a different site than the sender",
    "suspicious-admin-path": "Suspicious Admin Path — link points at a website admin login (common in scams)",
    "sender-display-mismatch": "Sender Display Mismatch — display name brand does not match the real sender domain",
    "url-shortener": "URL Shortener — link hides its real destination behind a short link",
    "suspicious-tld": "Suspicious TLD — link uses a domain ending often abused in scams",
    "typosquat-domain": "Typosquat Domain — link domain looks like a misspelled major brand",
    "dangerous-attachment": "Dangerous Attachment — file type can run code or install software on your Mac",
    "excessive-links": "Excessive Links — unusually high number of links for a normal email",
    "remote-images": "Remote Images — message loads many images from external websites",
    "hidden-link": "Hidden Link — visible link text does not reveal the real destination domain",
    "message-attachments": "Attachment Included — this message contains file attachment(s)",
  };

  const FLAG_SEVERITY = {
    "double-extension": "high",
    "fake-unsubscribe": "high",
    "mismatched-destination": "high",
    "ip-address": "high",
    "homograph-link": "high",
    "provider-warning": "high",
    "brand-impersonation": "high",
    "cta-domain-mismatch": "high",
    "suspicious-admin-path": "high",
    "dangerous-attachment": "high",
    "typosquat-domain": "high",
    "sender-display-mismatch": "medium",
    "url-shortener": "medium",
    "suspicious-tld": "medium",
    "hidden-link": "medium",
    "insecure-http": "low",
    "mismatch-return": "medium",
    "urgent-timer": "medium",
    "missing-profile-icon": "low",
    "blurry-graphics": "low",
    "broken-layout": "low",
    "generic-attachment-icon": "low",
    "excessive-links": "low",
    "remote-images": "low",
    "message-attachments": "low",
  };

  /** Point weights used by the expandable risk report (0–100 scale). */
  const FLAG_SCORE = {
    "cta-domain-mismatch": 20,
    "mismatched-destination": 20,
    "hidden-link": 18,
    "sender-display-mismatch": 18,
    "ip-address": 30,
    "double-extension": 40,
    "dangerous-attachment": 40,
    "brand-impersonation": 25,
    "suspicious-admin-path": 35,
    "homograph-link": 25,
    "typosquat-domain": 22,
    "url-shortener": 15,
    "suspicious-tld": 18,
    "fake-unsubscribe": 28,
    "provider-warning": 20,
    "mismatch-return": 15,
    "urgent-timer": 10,
    "insecure-http": 5,
    "missing-profile-icon": 4,
    "blurry-graphics": 4,
    "broken-layout": 6,
    "generic-attachment-icon": 5,
    "excessive-links": 8,
    "remote-images": 5,
    "message-attachments": 6,
  };

  const RELIEF_SCORE = {
    "auth-signed-by": -10,
    "auth-mailed-by": -8,
    "auth-aligned": -12,
  };

  const SEVERITY_RANK = { low: 1, medium: 2, high: 3 };

  const SEVERITY_COPY = {
    high: "High risk",
    medium: "Medium risk",
    low: "Low risk",
  };

  const IS_TOP_FRAME = window.self === window.top;
  const PROTON_FRAME_READY = "dynamickey-proton-frame-ready";
  const PROTON_SCAN_RESULT = "dynamickey-proton-scan-result";
  const PROTON_SCAN_STORAGE_KEY = "dynamickey-proton-scan";
  let pendingProtonIframeFlags = [];
  let pendingProtonIframeIdentity = null;
  let protonScanHeartbeat = null;

  if (isExtensionContextValid()) {
    try {
      browserAPI.storage.local.get([STORAGE_KEY, TRUSTED_DOMAINS_KEY], (result) => {
        if (result[STORAGE_KEY] === undefined) {
          mailShieldEnabled = true;
        } else {
          mailShieldEnabled = Boolean(result[STORAGE_KEY]);
        }

        const list = result[TRUSTED_DOMAINS_KEY];
        trustedDomains = Array.isArray(list)
          ? list.map((domain) => String(domain).trim().toLowerCase())
          : [];
      });
    } catch {
      // Ignore invalid extension context during initial storage read.
    }
  }

  browserAPI.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") {
      return;
    }

    if (changes[STORAGE_KEY]) {
      mailShieldEnabled = Boolean(changes[STORAGE_KEY].newValue);
      if (!mailShieldEnabled) {
        hideBanner();
        hideLinkHover();
      } else {
        scheduleScan();
      }
    }

    if (changes[TRUSTED_DOMAINS_KEY]) {
      const list = changes[TRUSTED_DOMAINS_KEY].newValue;
      trustedDomains = Array.isArray(list)
        ? list.map((domain) => String(domain).trim().toLowerCase())
        : [];
      scheduleScan();
    }
  });

  /** Resolves the mail host when running inside Proton's about:blank content iframe. */
  function resolveMailHostname() {
    const host = location.hostname.toLowerCase();
    if (host === "mail.proton.me" || host === "mail.protonmail.com") {
      return host;
    }

    if (host && host !== "blank") {
      return host;
    }

    try {
      const parentHost = window.parent?.location?.hostname?.toLowerCase() ?? "";
      if (parentHost) {
        return parentHost;
      }
    } catch {
      // Ignore cross-origin parent lookups.
    }

    try {
      const topHost = window.top?.location?.hostname?.toLowerCase() ?? "";
      if (topHost) {
        return topHost;
      }
    } catch {
      // Ignore cross-origin top lookups.
    }

    return host;
  }

  /** True when this frame is Proton's sandboxed HTML mail iframe. */
  function isProtonMailContentFrame() {
    if (document.getElementById("proton-root") instanceof HTMLElement) {
      return true;
    }

    if (window.frameElement instanceof HTMLIFrameElement) {
      const frameTestId = window.frameElement.getAttribute("data-testid") ?? "";
      const frameTitle = window.frameElement.getAttribute("title") ?? "";
      if (frameTestId === "content-iframe" || /email content/i.test(frameTitle)) {
        return true;
      }
    }

    return false;
  }

  /** @returns {boolean} */
  function isWebmailHost() {
    const host = resolveMailHostname();
    if (
      host === "mail.google.com"
      || host.includes("outlook.live.com")
      || host.includes("outlook.office.com")
      || host.includes("outlook.office365.com")
      || host === "mail.yahoo.com"
      || host.includes("mail.yahoo.")
      || host === "mail.proton.me"
      || host === "mail.protonmail.com"
      || host.includes("mail.")
    ) {
      return true;
    }

    if (document.getElementById("proton-root")) {
      return true;
    }

    if (window.frameElement instanceof HTMLIFrameElement) {
      const frameTestId = window.frameElement.getAttribute("data-testid") ?? "";
      if (frameTestId === "content-iframe" || /message/i.test(frameTestId)) {
        return true;
      }
    }

    return false;
  }

  /** Returns the current webmail provider slug for provider-specific DOM lookups. */
  function webmailProvider() {
    if (isProtonMailContentFrame()) {
      return "proton";
    }

    const host = resolveMailHostname();
    if (host === "mail.google.com") {
      return "gmail";
    }
    if (
      host.includes("outlook.live.com")
      || host.includes("outlook.office.com")
      || host.includes("outlook.office365.com")
    ) {
      return "outlook";
    }
    if (host === "mail.yahoo.com" || host.includes("mail.yahoo.")) {
      return "yahoo";
    }
    if (host === "mail.proton.me" || host === "mail.protonmail.com" || host.includes("proton.me")) {
      return "proton";
    }

    if (location.hostname === "mail.proton.me" || location.hostname === "mail.protonmail.com") {
      return "proton";
    }

    return "generic";
  }

  /** Finds the open/expanded message container in the reading pane (not the thread list). */
  function findOpenMessageContainer() {
    const provider = webmailProvider();
    const main = document.querySelector('[role="main"]');

    if (provider === "gmail" && main instanceof HTMLElement) {
      const expandedHeader = main.querySelector(".gs .gE.iv.gt, .gs .gE");
      if (expandedHeader instanceof HTMLElement) {
        return expandedHeader.closest(".gs") ?? expandedHeader.parentElement;
      }
    }

    if (provider === "outlook") {
      const outlookReaders = [
        "#ReadingPaneContainer",
        '[data-app-section="ReadingPane"]',
        '[role="main"] [data-testid="messageBody"]',
        '[role="main"] div[role="document"]',
        "#mail-reader-container",
      ];
      for (const selector of outlookReaders) {
        const reader = document.querySelector(selector);
        if (reader instanceof HTMLElement) {
          return reader;
        }
      }
    }

    if (provider === "yahoo") {
      const yahooReaders = [
        "#message-view",
        ".message-view",
        '[data-test-id="message-view-body"]',
        ".msg-body",
      ];
      for (const selector of yahooReaders) {
        const reader = document.querySelector(selector);
        if (reader instanceof HTMLElement) {
          return reader;
        }
      }
    }

    if (provider === "proton") {
      const protonReaders = [
        '[data-testid^="message-header-expanded"]',
        ".message-header-expanded",
        '[data-testid="message:message-header-metas"]',
        ".message-header-from-container",
        '[data-testid="message-view"]',
        '[data-testid="message-container"]',
        ".message-container",
        '[class*="messageContent"]',
        '[role="main"]',
      ];
      for (const selector of protonReaders) {
        const reader = document.querySelector(selector);
        if (reader instanceof HTMLElement) {
          return reader;
        }
      }
    }

    if (main instanceof HTMLElement) {
      const fromBody = findMessageRoot()?.closest(".gs, [data-message-id], [data-legacy-message-id]");
      if (fromBody instanceof HTMLElement) {
        return fromBody;
      }

      const reader = main.querySelector("#mail-reader-container, [data-test-id='message-view-body']");
      if (reader instanceof HTMLElement) {
        return reader;
      }

      const generic = main.querySelector("[data-message-id], [data-legacy-message-id]");
      if (generic instanceof HTMLElement) {
        return generic;
      }
    }

    return null;
  }

  /** Finds the currently open email message root in the page DOM. */
  function findMessageRoot() {
    const provider = webmailProvider();

    if (provider === "gmail") {
      const gmailSelectors = [
        ".gs .a3s.aiL",
        '[role="main"] .a3s.aiL',
        ".a3s.aiL",
        '[aria-label="Message Body"]',
      ];
      for (const selector of gmailSelectors) {
        const node = document.querySelector(selector);
        if (node instanceof HTMLElement && node.textContent.trim().length > 0) {
          return node;
        }
      }
    }

    if (provider === "proton") {
      const protonBody = findProtonEmailBody();
      if (protonBody instanceof HTMLElement) {
        return protonBody;
      }

      return null;
    }

    const selectors = provider === "outlook"
      ? [
        '[role="main"] [data-testid="messageBody"]',
        '[role="main"] div[role="document"]',
        "#ReadingPaneContainer [role=\"document\"]",
        ".allowTextSelection",
        "#mail-reader-container",
      ]
      : provider === "yahoo"
        ? [
          "#message-view .msg-body",
          ".message-view .msg-body",
          '[data-test-id="message-view-body"]',
          ".msg-body",
        ]
        : provider === "proton"
          ? [
            '[data-testid="message-content"]',
            ".message-container",
          ]
          : [
          '[role="main"] [data-message-id]',
          '[role="main"] .a3s.aiL',
          '[aria-label="Message Body"]',
          '[role="listitem"][data-legacy-message-id]',
          '.wide-content-host .a3s.aiL',
          '.message-body',
          '#mail-reader-container',
          '[data-test-id="message-view-body"]',
        ];

    for (const selector of selectors) {
      const node = document.querySelector(selector);
      if (node instanceof HTMLElement && node.textContent.trim().length > 0) {
        return node;
      }
    }

    return null;
  }

  /** Finds each visible message body block in the open conversation (forwards, reply stacks). */
  function findThreadMessageBlocks() {
    const provider = webmailProvider();
    /** @type {Array<{ root: HTMLElement, container: HTMLElement, index: number }>} */
    const blocks = [];
    const seen = new Set();

    const addBlock = (root, container) => {
      if (!(root instanceof HTMLElement) || !(container instanceof HTMLElement)) {
        return;
      }
      if (root.textContent.trim().length === 0 || seen.has(root)) {
        return;
      }
      seen.add(root);
      blocks.push({ root, container, index: blocks.length });
    };

    if (provider === "gmail") {
      const main = document.querySelector('[role="main"]');
      if (main instanceof HTMLElement) {
        main.querySelectorAll(".gs").forEach((node) => {
          if (!(node instanceof HTMLElement)) {
            return;
          }
          const body = node.querySelector(".a3s.aiL, [aria-label=\"Message Body\"]");
          if (body instanceof HTMLElement) {
            addBlock(body, node);
          }
        });
      }
    }

    if (provider === "outlook") {
      const reader = document.querySelector(
        "#ReadingPaneContainer, [data-app-section=\"ReadingPane\"], [role=\"main\"]"
      );
      if (reader instanceof HTMLElement) {
        reader.querySelectorAll('[role="document"], [data-testid="messageBody"]').forEach((node) => {
          if (node instanceof HTMLElement) {
            addBlock(node, node.closest("[data-app-section=\"ReadingPane\"], #ReadingPaneContainer, article, div") ?? node);
          }
        });
      }
    }

    if (provider === "proton") {
      const protonBody = findProtonEmailBody();
      if (protonBody instanceof HTMLElement) {
        const container = protonBody.closest(
          '[data-testid="message-view"], [data-testid="message-container"], [role="main"]'
        ) ?? protonBody;
        addBlock(protonBody, container instanceof HTMLElement ? container : protonBody);
      }
    }

    if (provider === "yahoo") {
      const reader = document.querySelector("#message-view, .message-view, [role=\"main\"]");
      if (reader instanceof HTMLElement) {
        reader.querySelectorAll(".msg-body, [data-test-id=\"message-view-body\"]").forEach((node) => {
          if (node instanceof HTMLElement) {
            addBlock(node, node.parentElement instanceof HTMLElement ? node.parentElement : node);
          }
        });
      }
    }

    if (blocks.length === 0) {
      const fallbackRoot = findMessageRoot();
      if (fallbackRoot instanceof HTMLElement) {
        const container = findAttachmentScanRoot(fallbackRoot) ?? fallbackRoot;
        addBlock(fallbackRoot, container instanceof HTMLElement ? container : fallbackRoot);
      }
    }

    return blocks;
  }

  /** Counts Gmail/Outlook forward separators embedded inside one visible message body. */
  function countForwardedMessageMarkers(text) {
    const source = String(text ?? "");
    /** @type {Array<RegExp>} */
    const markerPatterns = [
      /-{3,}\s*forwarded message\s*-{3,}/gi,
      /begin forwarded message/gi,
      /-{3,}\s*original message\s*-{3,}/gi,
    ];
    let markerCount = 0;
    for (const pattern of markerPatterns) {
      const matches = source.match(pattern);
      if (matches?.length) {
        markerCount = Math.max(markerCount, matches.length);
      }
    }
    return markerCount;
  }

  /** Estimates how many messages were scanned in the open thread or stacked forward. */
  function countThreadMessagesScanned(threadBlocks = null) {
    const blocks = threadBlocks ?? findThreadMessageBlocks();
    const provider = webmailProvider();
    let estimated = blocks.length;

    if (provider === "gmail") {
      const main = document.querySelector('[role="main"]');
      if (main instanceof HTMLElement) {
        const gsRows = [...main.querySelectorAll(".gs")].filter((node) =>
          node instanceof HTMLElement
          && node.querySelector(".gE, [data-message-id], .a3s.aiL, [aria-label=\"Message Body\"]")
        );
        estimated = Math.max(estimated, gsRows.length);

        const forwardMarkers = countForwardedMessageMarkers(main.innerText ?? "");
        if (forwardMarkers > 0) {
          estimated = Math.max(estimated, forwardMarkers + 1);
        }
      }
    }

    if (provider === "outlook") {
      const reader = document.querySelector(
        "#ReadingPaneContainer, [data-app-section=\"ReadingPane\"], [role=\"main\"]"
      );
      if (reader instanceof HTMLElement) {
        const messageBodies = reader.querySelectorAll('[role="document"], [data-testid="messageBody"]');
        estimated = Math.max(estimated, messageBodies.length);
        const forwardMarkers = countForwardedMessageMarkers(reader.innerText ?? "");
        if (forwardMarkers > 0) {
          estimated = Math.max(estimated, forwardMarkers + 1);
        }
      }
    }

    return Math.max(estimated, 1);
  }

  /** Builds the always-visible scan scope line for the warning banner. */
  function formatThreadScanScope(report) {
    const messageCount = report?.threadMessageCount ?? 1;
    const collapsedCount = report?.collapsedMentionCount ?? 0;
    const collapsedSuffix = collapsedCount > 0
      ? ` · ${collapsedCount} duplicate mention${collapsedCount === 1 ? "" : "s"} collapsed`
      : "";

    if (messageCount > 1) {
      return `Scanned all ${messageCount} messages in this stacked conversation${collapsedSuffix}`;
    }

    return `Scanned 1 message${collapsedSuffix}`;
  }

  /** Builds a stable grouping key for thread-aware flag deduplication. */
  function flagGroupKey(flag) {
    let detail = String(flag?.detail ?? "").trim().toLowerCase();
    if (
      flag?.id === "double-extension"
      || flag?.id === "dangerous-attachment"
      || flag?.id === "message-attachments"
    ) {
      detail = sanitizeAttachmentFilename(flag.detail ?? "").toLowerCase();
    }
    return `${flag?.id ?? "unknown"}:${detail}`;
  }

  /** Normalizes a flag detail string for display after Gmail/forward UI noise is stripped. */
  function normalizeFlagDetailForDisplay(flag) {
    if (
      flag.id === "double-extension"
      || flag.id === "dangerous-attachment"
      || flag.id === "message-attachments"
    ) {
      const cleaned = sanitizeAttachmentFilename(flag.detail ?? "");
      if (cleaned) {
        return cleaned;
      }
    }
    return String(flag.detail ?? "").trim();
  }

  /** Normalizes attachment flags so Gmail UI labels collapse to one basename. */
  function normalizeFlagForThreadGrouping(flag) {
    if (!flag?.id) {
      return flag;
    }

    const next = { ...flag };
    if (
      flag.id === "double-extension"
      || flag.id === "dangerous-attachment"
      || flag.id === "message-attachments"
    ) {
      const clean = sanitizeAttachmentFilename(flag.detail ?? "");
      if (clean) {
        next._sourceDetail = String(next._sourceDetail ?? flag.detail ?? clean).trim();
        next.detail = clean;
      }
    }

    return next;
  }

  /** Groups duplicate flags across a stacked thread for scoring and the expandable report. */
  function consolidateThreadFlags(flags, threadMessageCount) {
    /** @type {Map<string, { id: string, occurrences: string[], messageIndexes: Set<number>, attachmentSourceCount: number }>} */
    const groups = new Map();
    let rawMentionCount = 0;

    for (const flag of flags.map(normalizeFlagForThreadGrouping)) {
      if (!flag?.id) {
        continue;
      }

      rawMentionCount += 1;
      const key = flagGroupKey(flag);
      if (!groups.has(key)) {
        groups.set(key, {
          id: flag.id,
          occurrences: [],
          messageIndexes: new Set(),
          attachmentSourceCount: 0,
        });
      }

      const group = groups.get(key);
      const sourceDetail = String(flag._sourceDetail ?? flag.detail ?? "").trim();
      if (sourceDetail) {
        group.occurrences.push(sourceDetail);
      }
      if (Number.isFinite(flag._threadMessage)) {
        group.messageIndexes.add(flag._threadMessage);
      }
      if (Number.isFinite(flag._attachmentSourceCount)) {
        group.attachmentSourceCount = Math.max(group.attachmentSourceCount, flag._attachmentSourceCount);
      }
    }

    /** @type {Array<{ id: string, detail?: string, threadNote?: string }>} */
    const displayFlags = [];
    /** @type {Array<{ text: string, points: string, positive: boolean }>} */
    const groupedEvidence = [];

    for (const group of groups.values()) {
      const uniqueSources = new Set(group.occurrences.map((entry) => entry.trim()).filter(Boolean));
      const displayDetail = normalizeFlagDetailForDisplay({
        id: group.id,
        detail: group.occurrences[0] ?? "",
      });
      const messagesTagged = [...group.messageIndexes].sort((left, right) => left - right);
      const mentionCount = Math.max(
        uniqueSources.size,
        group.occurrences.length,
        group.attachmentSourceCount,
        1
      );
      const duplicateMentions = Math.max(0, mentionCount - 1);
      const threadNotes = [];

      if (duplicateMentions > 0) {
        if (threadMessageCount > 1) {
          threadNotes.push(`${mentionCount} mentions collapsed across ${threadMessageCount} messages`);
        } else {
          threadNotes.push(`${mentionCount} mentions collapsed`);
        }
      }
      if (messagesTagged.length > 1) {
        threadNotes.push(`messages ${messagesTagged.join(", ")}`);
      } else if (threadMessageCount > 1 && messagesTagged.length === 1) {
        threadNotes.push(`message ${messagesTagged[0]}`);
      }

      const threadNote = threadNotes.join(" · ");
      displayFlags.push({
        id: group.id,
        detail: displayDetail || undefined,
        threadNote: threadNote || undefined,
      });

      const baseCopy = FLAG_COPY[group.id] ?? group.id;
      const detailSuffix = displayDetail ? ` (${displayDetail})` : "";
      let evidenceText = `${baseCopy}${detailSuffix}`;
      if (threadNote) {
        evidenceText += ` — ${threadNote}`;
      }

      groupedEvidence.push({
        text: evidenceText,
        points: `+${FLAG_SCORE[group.id] ?? 8}`,
        positive: true,
      });
    }

    const scoringFlags = displayFlags.map((flag) => ({
      id: flag.id,
      detail: flag.detail,
    }));

    return {
      displayFlags,
      scoringFlags,
      groupedEvidence,
      threadMessageCount: Math.max(threadMessageCount, 1),
      uniqueRiskCount: displayFlags.length,
      rawMentionCount,
      collapsedMentionCount: Math.max(0, rawMentionCount - displayFlags.length),
      isStackedThread: threadMessageCount > 1,
    };
  }

  /** Tags each raw scan flag with the thread message index it came from. */
  function tagFlagsForThread(flags, threadMessage) {
    return flags.map((flag) => ({
      ...flag,
      _threadMessage: threadMessage,
      _sourceDetail: flag.detail ?? "",
    }));
  }

  /** Reads the sender address from Proton Mail's recipients:sender header chip. */
  function extractProtonSenderEmail() {
    const senderRoot = document.querySelector(
      '[data-testid="recipients:sender"], .message-header-from-container [data-testid^="recipient:details-dropdown"], .message-header-recipient-mobile [data-testid^="recipient:details-dropdown"]'
    );
    if (!(senderRoot instanceof HTMLElement)) {
      return null;
    }

    if (senderRoot instanceof HTMLAnchorElement && senderRoot.href.startsWith("mailto:")) {
      const email = senderRoot.href.replace(/^mailto:/i, "").split("?")[0].trim();
      if (email.includes("@")) {
        return email;
      }
    }

    const mailto = senderRoot.querySelector('a[href^="mailto:"]');
    if (mailto instanceof HTMLAnchorElement) {
      const email = mailto.href.replace(/^mailto:/i, "").split("?")[0].trim();
      if (email.includes("@")) {
        return email;
      }
    }

    const addressNode = senderRoot.querySelector('[data-testid="recipient-address"]');
    const candidateText = [
      senderRoot.getAttribute("title") ?? "",
      addressNode?.textContent ?? "",
      senderRoot.textContent ?? "",
    ].join(" ");
    const match = candidateText.match(/[\w.+-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
    return match ? match[0].trim() : null;
  }

  /** Reads Proton Mail HTML bodies rendered inside same-origin content iframes. */
  function findProtonEmailBody() {
    /** @type {HTMLElement[]} */
    const candidates = [];
    const seenRoots = new Set();

    const collectFromFrame = (frame) => {
      if (!(frame instanceof HTMLIFrameElement)) {
        return;
      }

      try {
        const frameDocument = frame.contentDocument;
        const protonRoot = frameDocument?.getElementById("proton-root");
        if (protonRoot instanceof HTMLElement && !seenRoots.has(protonRoot)) {
          seenRoots.add(protonRoot);
          candidates.push(protonRoot);
          return;
        }

        const frameBody = frameDocument?.body;
        if (frameBody instanceof HTMLElement && frameBody.textContent.trim().length > 10 && !seenRoots.has(frameBody)) {
          seenRoots.add(frameBody);
          candidates.push(frameBody);
        }
      } catch {
        // Ignore cross-origin frames.
      }
    };

    document.querySelectorAll(
      'iframe[data-testid="content-iframe"], iframe[title*="Email content" i], iframe[sandbox][src="about:blank"], iframe[sandbox]'
    ).forEach(collectFromFrame);

    document.querySelectorAll("iframe").forEach(collectFromFrame);

    if (candidates.length === 0) {
      const localRoot = document.getElementById("proton-root");
      if (localRoot instanceof HTMLElement) {
        candidates.push(localRoot);
      }
    }

    candidates.sort((left, right) => {
      const leftLinks = left.querySelectorAll("a[href]").length;
      const rightLinks = right.querySelectorAll("a[href]").length;
      if (rightLinks !== leftLinks) {
        return rightLinks - leftLinks;
      }
      return (right.textContent?.trim().length ?? 0) - (left.textContent?.trim().length ?? 0);
    });

    return candidates[0] ?? null;
  }

  /** Finds Proton attachment chips rendered outside the HTML body iframe. */
  function findProtonAttachmentRoot() {
    const attachmentItems = document.querySelectorAll(
      '[data-testid="attachment-item"], [data-testid^="attachment-item:"], [data-testid="attachment-list:header"]'
    );
    if (attachmentItems.length === 0) {
      return null;
    }

    const messageHeader = document.querySelector(
      '[data-testid^="message-header-expanded"], [data-testid^="message-header-collapsed"]'
    );
    if (messageHeader instanceof HTMLElement) {
      let node = messageHeader.parentElement;
      while (node instanceof HTMLElement) {
        if (node.querySelector('[data-testid="attachment-item"], [data-testid^="attachment-item:"]')) {
          return node;
        }
        node = node.parentElement;
      }
    }

    const listHeader = document.querySelector('[data-testid="attachment-list:header"]');
    if (listHeader instanceof HTMLElement) {
      return listHeader.closest(".composer-attachment-list-wrapper, .message-attachmentList, section, div")
        ?? listHeader.parentElement;
    }

    return attachmentItems[0]?.parentElement ?? null;
  }

  /** Extracts a clean attachment filename from Proton attachment DOM metadata. */
  function normalizeProtonAttachmentFilename(value) {
    const raw = String(value ?? "").trim();
    if (!raw) {
      return null;
    }

    const fromTestId = raw.match(/^attachment-item:(.+?)--(?:primary|secondary)-action$/i)?.[1];
    if (fromTestId) {
      return fromTestId.trim();
    }

    if (/^[\w.-]+\.[a-z0-9]{2,8}(?:\.[a-z0-9]{2,8})?$/i.test(raw)) {
      return raw;
    }

    return null;
  }

  /** Extracts the real attachment basename from metadata, labels, or UI button text. */
  function extractAttachmentBasename(raw) {
    const fromProtonMeta = normalizeProtonAttachmentFilename(String(raw ?? ""));
    if (fromProtonMeta) {
      return fromProtonMeta;
    }

    const match = String(raw ?? "").match(
      /([\w][\w.-]*\.(?:pdf|docx?|rtf|txt|zip|xls|png|jpe?g|dmg|app|exe|scr|bat|js|vbs|cmd|msi|apk)(?:\.(?:rtf|exe|dmg|app|scr|bat|js|vbs|cmd|msi|apk))?)/i
    );
    if (match?.[1]) {
      return match[1].trim();
    }

    return null;
  }

  /** Pulls a clean filename out of noisy Proton attachment row text. */
  function sanitizeAttachmentFilename(raw) {
    const basename = extractAttachmentBasename(raw);
    if (basename) {
      return basename;
    }

    return String(raw ?? "").trim().slice(0, 80);
  }

  /** Collects attachment filenames from Proton's footer/header attachment UI. */
  function collectProtonAttachmentNames() {
    /** @type {Set<string>} */
    const names = new Set();

    document.querySelectorAll('[data-testid^="attachment-item:"]').forEach((node) => {
      const filename = normalizeProtonAttachmentFilename(node.getAttribute("data-testid") ?? "");
      if (filename) {
        names.add(filename);
      }
    });

    if (names.size > 0) {
      return [...names];
    }

    document.querySelectorAll('[data-testid="attachment-item"]').forEach((node) => {
      const primaryAction = node.querySelector('[data-testid^="attachment-item:"][data-testid$="--primary-action"]');
      const filename = normalizeProtonAttachmentFilename(primaryAction?.getAttribute("data-testid") ?? "");
      if (filename) {
        names.add(filename);
      }
    });

    return [...names];
  }

  /** Builds attachment warning flags from normalized filenames. */
  function buildAttachmentFlagsFromNames(names) {
    /** @type {Array<{ id: string, detail?: string }>} */
    const flags = [];
    const seen = new Set();

    for (const rawName of names) {
      const name = sanitizeAttachmentFilename(rawName);
      if (!name) {
        continue;
      }

      const key = name.toLowerCase();
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);

      const lowered = name.toLowerCase();
      const dangerousExtension = DANGEROUS_ATTACHMENT_EXTENSIONS.find((ext) => {
        const doublePattern = new RegExp(`\\.(${ext})$`, "i");
        const hiddenPattern = new RegExp(`\\.(pdf|docx?|txt|jpg|png|zip|xls)x?\\.(${ext})$`, "i");
        return hiddenPattern.test(lowered) || doublePattern.test(lowered);
      });

      if (/\.(pdf|docx?|txt|jpg|png|zip|xls)x?\.(exe|scr|bat|js|vbs|cmd|msi|apk)$/i.test(name)) {
        flags.push({ id: "double-extension", detail: name });
      } else if (/\.(pdf|docx?|txt|jpg|png|zip|xls)\.(rtf|exe|scr|bat|js|vbs|cmd|msi|apk|dmg|app)$/i.test(lowered)) {
        flags.push({ id: "double-extension", detail: name });
      } else if (dangerousExtension) {
        flags.push({ id: "dangerous-attachment", detail: name });
      } else if (/\.(exe|scr|bat|js|vbs|cmd|msi|apk)$/i.test(name)) {
        flags.push({ id: "double-extension", detail: name });
      }
    }

    return flags;
  }

  /** Scans Proton attachment chips once using structured filename metadata. */
  function scanProtonAttachments() {
    return buildAttachmentFlagsFromNames(collectProtonAttachmentNames());
  }

  /** Adds a low-risk attachment notice when a suspicious message also has files attached. */
  function appendProtonAttachmentNotice(flags) {
    if (webmailProvider() !== "proton" || !IS_TOP_FRAME || flags.length === 0) {
      return flags;
    }

    if (flags.some((flag) => flag.id === "message-attachments")) {
      return flags;
    }

    const attachmentNames = collectProtonAttachmentNames();
    if (attachmentNames.length === 0) {
      return flags;
    }

    const alreadyFlagged = attachmentNames.every((name) =>
      flags.some((flag) => (
        flag.id === "double-extension"
        || flag.id === "dangerous-attachment"
      ) && sanitizeAttachmentFilename(flag.detail ?? "").toLowerCase() === name.toLowerCase())
    );
    if (alreadyFlagged) {
      return flags;
    }

    return [
      ...flags,
      {
        id: "message-attachments",
        detail: attachmentNames.slice(0, 3).join(", "),
      },
    ];
  }

  /** True when the top frame can read Proton HTML mail directly from the content iframe. */
  function canReadProtonIframeDirectly() {
    if (webmailProvider() !== "proton" || !IS_TOP_FRAME) {
      return false;
    }

    const frame = document.querySelector('iframe[data-testid="content-iframe"]');
    if (!(frame instanceof HTMLIFrameElement)) {
      return false;
    }

    try {
      const protonRoot = frame.contentDocument?.getElementById("proton-root");
      return protonRoot instanceof HTMLElement && protonRoot.textContent.trim().length > 0;
    } catch {
      return false;
    }
  }

  /** Stable Proton message id shared between the top frame and the mail iframe. */
  function getProtonBridgeIdentity() {
    return getProtonMessageIdentityFromTop() ?? (webmailProvider() === "proton" ? getMessageIdentity() : null);
  }

  /** Reads the open Proton message id from the top-frame URL (works inside mail iframes). */
  function getProtonMessageIdentityFromTop() {
    try {
      const pathname = window.top?.location?.pathname ?? location.pathname;
      const urlMessageId = pathname.match(
        /\/(?:inbox|drafts|sent|trash|spam|archive|starred|all|snoozed|outbox|label\/[^/]+)\/([^/?#]+)/i
      )?.[1];
      if (urlMessageId && urlMessageId.length > 8) {
        return `proton-url:${urlMessageId.slice(0, 160)}`;
      }
    } catch {
      // Ignore cross-origin top lookups.
    }

    return null;
  }

  /** Pulls link/body flags from Proton's sandboxed iframe via the extension scripting API (Brave). */
  function fetchProtonIframeFlagsViaScripting() {
    return new Promise((resolve) => {
      if (canReadProtonIframeDirectly() || !browserAPI.runtime?.sendMessage) {
        resolve([]);
        return;
      }

      safeRuntimeSendMessage({ type: "SCAN_PROTON_IFRAME" }, (response) => {
        if (response?.ok === false) {
          resolve([]);
          return;
        }
        const flags = response?.result?.flags;
        resolve(Array.isArray(flags) ? flags : []);
      });
    });
  }

  /** Requests a Chromium iframe scan and merges the results into the active Proton warning. */
  async function pullProtonIframeFlagsFromScripting() {
    if (canReadProtonIframeDirectly()) {
      return [];
    }

    const flags = await fetchProtonIframeFlagsViaScripting();
    if (flags.length === 0) {
      return [];
    }

    applyProtonIframeFlags(flags, getProtonBridgeIdentity() ?? getMessageIdentity());
    return flags;
  }

  /** Presents the latest merged Proton warning without waiting for the async rescan loop. */
  function refreshProtonWarningBanner() {
    if (webmailProvider() !== "proton" || !IS_TOP_FRAME || !mailShieldEnabled || shouldSkipBanner()) {
      return;
    }

    if (!hasProtonMessageOpen()) {
      return;
    }

    const identity = getProtonBridgeIdentity() ?? getMessageIdentity();
    const messageRoot = findMessageRoot();
    const rawFlags = mergeProtonScanFlags(scanOpenMessage());
    const resolvedFlags = filterNoiseOnlyWarnings(
      rawFlags,
      extractSenderDomain(),
      messageRoot
    );
    if (resolvedFlags.length === 0) {
      return;
    }

    presentWarning(identity, resolvedFlags);
  }

  /** Publishes iframe scan results for the top frame (postMessage + runtime relay for Brave). */
  function publishProtonIframeFlags(flags) {
    if (!Array.isArray(flags) || flags.length === 0) {
      return;
    }

    const identity = getProtonMessageIdentityFromTop() ?? getMessageIdentity();
    const payload = {
      at: Date.now(),
      flags,
      identity,
    };

    try {
      window.top?.sessionStorage?.setItem(PROTON_SCAN_STORAGE_KEY, JSON.stringify(payload));
    } catch {
      // Ignore storage bridge failures.
    }

    let targetOrigin = "*";
    try {
      targetOrigin = window.top?.location?.origin || location.origin || "*";
    } catch {
      targetOrigin = "*";
    }

    try {
      window.top?.postMessage({
        type: PROTON_FRAME_READY,
        flags,
        identity,
      }, targetOrigin);
    } catch {
      // Ignore if the top frame is unreachable.
    }

    safeRuntimeSendMessage({
      type: "PROTON_IFRAME_SCAN",
      flags,
      identity,
    });
  }

  /** Reads iframe scan results published through sessionStorage (same-frame fallback). */
  function consumeProtonIframeBridge() {
    try {
      const raw = sessionStorage.getItem(PROTON_SCAN_STORAGE_KEY);
      if (!raw) {
        return;
      }

      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed?.flags) || Date.now() - Number(parsed.at ?? 0) > 45000) {
        return;
      }

      const bridgeIdentity = parsed.identity ?? null;
      const currentIdentity = getProtonBridgeIdentity() ?? getMessageIdentity();
      if (
        bridgeIdentity
        && currentIdentity
        && bridgeIdentity !== currentIdentity
      ) {
        return;
      }

      if (
        bridgeIdentity
        && pendingProtonIframeIdentity
        && bridgeIdentity !== pendingProtonIframeIdentity
      ) {
        pendingProtonIframeFlags = [];
      }

      pendingProtonIframeIdentity = bridgeIdentity ?? pendingProtonIframeIdentity ?? currentIdentity;
      pendingProtonIframeFlags = dedupeFlags([
        ...pendingProtonIframeFlags,
        ...parsed.flags,
      ]);
    } catch {
      // Ignore malformed bridge payloads.
    }
  }

  /** Stores iframe scan results and schedules a full top-frame merge. */
  function applyProtonIframeFlags(flags, bridgeIdentity = null) {
    if (!Array.isArray(flags) || flags.length === 0 || !IS_TOP_FRAME) {
      return;
    }

    const currentIdentity = getProtonBridgeIdentity() ?? getMessageIdentity();
    const resolvedBridgeIdentity = bridgeIdentity ?? pendingProtonIframeIdentity ?? currentIdentity;

    if (
      resolvedBridgeIdentity
      && currentIdentity
      && resolvedBridgeIdentity !== currentIdentity
    ) {
      return;
    }

    if (
      resolvedBridgeIdentity
      && pendingProtonIframeIdentity
      && resolvedBridgeIdentity !== pendingProtonIframeIdentity
    ) {
      pendingProtonIframeFlags = [];
    }

    pendingProtonIframeIdentity = resolvedBridgeIdentity ?? pendingProtonIframeIdentity;
    pendingProtonIframeFlags = dedupeFlags([
      ...pendingProtonIframeFlags,
      ...flags.map((flag) => ({
        ...flag,
        _threadMessage: 1,
        _sourceDetail: flag.detail ?? "",
      })),
    ]);
    refreshProtonWarningBanner();
  }

  /** Accepts postMessage events from Proton's about:blank mail iframe (Brave uses origin "null"). */
  function isTrustedProtonFrameMessage(event) {
    if (!event?.source || event.source === window) {
      return false;
    }

    if (event.origin === location.origin) {
      return true;
    }

    if (event.origin === "null") {
      return true;
    }

    const normalizedOrigin = String(event.origin ?? "").toLowerCase();
    return normalizedOrigin.endsWith(".proton.me")
      || normalizedOrigin.endsWith(".protonmail.com");
  }

  /** Clears cached warning state when the user leaves the current message. */
  function clearActiveWarningState(identity = null) {
    if (!identity || activeWarningState?.identity === identity) {
      activeWarningState = null;
    }
  }

  /** Reuses the last warning for this message when Proton rescans return empty briefly. */
  function getStickyWarningForIdentity(identity) {
    if (!identity || !activeWarningState) {
      return null;
    }

    if (activeWarningState.identity !== identity) {
      return null;
    }

    if (dismissedMessageId === identity) {
      return null;
    }

    return activeWarningState;
  }

  /** True when a Proton message is open even if the HTML body iframe is still loading. */
  function hasProtonMessageOpen() {
    if (webmailProvider() !== "proton" || !IS_TOP_FRAME) {
      return false;
    }

    if (findProtonEmailBody()) {
      return true;
    }

    return Boolean(
      document.querySelector(
        'iframe[data-testid="content-iframe"], [data-testid^="message-header-expanded"], [data-testid^="message-header-collapsed"], [data-testid="recipients:sender"]'
      )
    );
  }

  /** Expands scan scope to attachment chips that live outside the HTML body (Gmail .aZo row). */
  function findAttachmentScanRoot(messageRoot) {
    if (!(messageRoot instanceof HTMLElement)) {
      return messageRoot;
    }

    const provider = webmailProvider();
    if (provider === "gmail") {
      const messageBlock = messageRoot.closest(".gs, [data-legacy-message-id], [data-message-id]");
      if (messageBlock instanceof HTMLElement) {
        return messageBlock;
      }
    }

    if (provider === "outlook") {
      const messageBlock = messageRoot.closest(
        "#ReadingPaneContainer, [data-app-section=\"ReadingPane\"]"
      );
      if (messageBlock instanceof HTMLElement) {
        return messageBlock;
      }
    }

    if (provider === "proton") {
      const protonAttachmentRoot = findProtonAttachmentRoot();
      if (protonAttachmentRoot instanceof HTMLElement) {
        return protonAttachmentRoot;
      }

      const messageBlock = messageRoot.closest(
        '[data-testid^="message-header-expanded"], .message-header-expanded, [data-testid="message-view"], [data-testid="message-container"], [role="main"]'
      );
      if (messageBlock instanceof HTMLElement) {
        return messageBlock;
      }
    }

    return messageRoot;
  }

  /** Watches Proton iframes and rescans when HTML mail finishes loading. */
  function watchProtonMessageFrames() {
    if (webmailProvider() !== "proton") {
      return;
    }

    document.querySelectorAll("iframe").forEach((frame) => {
      if (!(frame instanceof HTMLIFrameElement)) {
        return;
      }
      if (frame.dataset.dynamicKeyMailShieldWatch === "1") {
        return;
      }
      frame.dataset.dynamicKeyMailShieldWatch = "1";
      frame.addEventListener("load", () => {
        scheduleScan();
      });
    });
  }
  function findHeaderRegion() {
    const openContainer = findOpenMessageContainer();
    if (openContainer instanceof HTMLElement) {
      const scopedHeader = openContainer.querySelector(
        ".gE.iv.gt, .gE, [data-test-id='message-header'], h2"
      );
      if (scopedHeader instanceof HTMLElement) {
        return scopedHeader;
      }
      return openContainer;
    }

    const selectors = [
      ".gE.iv.gt",
      '[role="main"] h2',
      ".wide-content-host",
      "#mail-reader-container",
      '[data-test-id="message-header"]',
    ];

    for (const selector of selectors) {
      const node = document.querySelector(selector);
      if (node instanceof HTMLElement) {
        return node;
      }
    }

    return document.querySelector('[role="main"]') ?? document.body;
  }

  /** Returns the narrow sender header strip (never the full message body). */
  function findSenderHeaderOnly() {
    const provider = webmailProvider();

    if (provider === "gmail") {
      const gmailHeader = document.querySelector(
        '.gs .gE.iv.gt, .gs .gE, [role="main"] .gE.iv.gt, [role="main"] .gE'
      );
      if (gmailHeader instanceof HTMLElement) {
        return gmailHeader;
      }
    }

    if (provider === "outlook") {
      const outlookHeader = document.querySelector(
        '#ReadingPaneContainer [data-testid="messageHeader"], #ReadingPaneContainer [aria-label*="Message header" i]'
      );
      if (outlookHeader instanceof HTMLElement) {
        return outlookHeader;
      }

      const fromRow = document.querySelector(
        '#ReadingPaneContainer [data-testid="From"], #ReadingPaneContainer [aria-label*="From" i]'
      );
      if (fromRow instanceof HTMLElement) {
        return fromRow.closest("div") ?? fromRow;
      }
    }

    if (provider === "proton") {
      const protonHeader = document.querySelector(
        '.message-header-from-container, [data-testid^="message-header-expanded"], .message-header-expanded'
      );
      if (protonHeader instanceof HTMLElement) {
        return protonHeader;
      }
    }

    const scopedHeader = findHeaderRegion().querySelector?.(
      ".gE.iv.gt, .gE, [data-test-id='message-header'], [data-testid='messageHeader']"
    );
    if (scopedHeader instanceof HTMLElement) {
      return scopedHeader;
    }

    return findHeaderRegion();
  }

  /** Parses the sender address from a webmail header block (From / Fra). */
  function parseSenderEmailFromHeaderText(text) {
    const headerText = String(text ?? "");
    const senderSection = headerText.split(/\b(?:to|til|cc|bcc)\b[:\s]/i)[0];

    const fromPatterns = [
      /\bfrom[:\s]+[^\n]*?<?([\w.+-]+@[a-z0-9.-]+\.[a-z]{2,})>?/i,
      /\bfra[:\s]+[^\n]*?<?([\w.+-]+@[a-z0-9.-]+\.[a-z]{2,})>?/i,
      /\bsender[:\s]+[^\n]*?<?([\w.+-]+@[a-z0-9.-]+\.[a-z]{2,})>?/i,
      /\bavsender[:\s]+[^\n]*?<?([\w.+-]+@[a-z0-9.-]+\.[a-z]{2,})>?/i,
      /\bfrom\b[\s\S]{0,80}?([\w.+-]+@[a-z0-9.-]+\.[a-z]{2,})/i,
    ];

    for (const pattern of fromPatterns) {
      const match = senderSection.match(pattern);
      if (match?.[1]) {
        return match[1].trim();
      }
    }

    return null;
  }

  /** Outlook-specific From row lookup — avoids reading the To/recipient address. */
  function extractOutlookFromEmail() {
    const fromSelectors = [
      '#ReadingPaneContainer [data-testid="From"]',
      '#ReadingPaneContainer [aria-label^="From" i]',
      '#ReadingPaneContainer [aria-label*="From:" i]',
      '[role="main"] [data-testid="From"]',
      '[role="main"] [aria-label^="From" i]',
    ];

    for (const selector of fromSelectors) {
      const node = document.querySelector(selector);
      if (!(node instanceof HTMLElement)) {
        continue;
      }

      const ariaLabel = node.getAttribute("aria-label") ?? "";
      if (/\bto[:\s]/i.test(ariaLabel) && !/\bfrom[:\s]/i.test(ariaLabel)) {
        continue;
      }

      const mailto = node.querySelector('a[href^="mailto:"]');
      if (mailto instanceof HTMLAnchorElement) {
        const email = mailto.href.replace(/^mailto:/i, "").split("?")[0].trim();
        if (email.includes("@")) {
          return email;
        }
      }

      const candidateText = [
        node.getAttribute("title") ?? "",
        ariaLabel,
        node.textContent ?? "",
      ].join(" ");
      const match = candidateText.match(/[\w.+-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
      if (match) {
        return match[0].trim();
      }
    }

    return null;
  }

  /** Rejects personal mailbox addresses that usually belong to the recipient, not the sender. */
  function resolveSenderEmailAddress(email) {
    if (!email) {
      return null;
    }

    const normalizedDomain = normalizeSenderDomain(email);
    if (PERSONAL_MAILBOX_DOMAINS.has(normalizedDomain)) {
      const outlookFrom = extractOutlookFromEmail();
      if (outlookFrom) {
        return outlookFrom;
      }
      return null;
    }

    return email.trim();
  }

  /** Ignores personal mailbox domains unless they came from a structured sender field. */
  function isLikelyRecipientMailboxDomain(domain, fromStructuredSenderField) {
    const normalized = normalizeSenderDomain(domain);
    if (!normalized || fromStructuredSenderField) {
      return false;
    }
    return PERSONAL_MAILBOX_DOMAINS.has(normalized);
  }

  /** Normalizes `@user.com`, `user@company.com`, or `company.com` to `company.com`. */
  function normalizeSenderDomain(value) {
    let normalized = String(value ?? "").trim().toLowerCase();
    if (normalized.startsWith("@")) {
      normalized = normalized.slice(1);
    }
    if (normalized.includes("@")) {
      const match = normalized.match(/@([a-z0-9.-]+\.[a-z]{2,})/i);
      if (match) {
        return match[1];
      }
    }
    if (/^([a-z0-9-]+\.)+[a-z]{2,}$/i.test(normalized)) {
      return normalized;
    }
    return domainFromText(normalized);
  }

  /** Reads the sender email from Gmail/Outlook/Yahoo DOM attributes when available. */
  function extractSenderEmailAddress() {
    const provider = webmailProvider();

    if (provider === "outlook") {
      const outlookFrom = extractOutlookFromEmail();
      if (outlookFrom) {
        return resolveSenderEmailAddress(outlookFrom);
      }
    }

    if (provider === "proton") {
      const protonFrom = extractProtonSenderEmail();
      if (protonFrom) {
        return resolveSenderEmailAddress(protonFrom);
      }

      const protonFromSelectors = [
        '[data-testid="recipients:sender"]',
        '[data-testid="recipient-address"]',
      ];
      for (const selector of protonFromSelectors) {
        const node = document.querySelector(selector);
        if (!(node instanceof HTMLElement)) {
          continue;
        }
        const text = `${node.getAttribute("title") ?? ""} ${node.textContent ?? ""}`;
        const match = text.match(/[\w.+-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
        if (match) {
          return resolveSenderEmailAddress(match[0].trim());
        }
      }
    }

    const header = findSenderHeaderOnly();
    if (!(header instanceof HTMLElement)) {
      return null;
    }

    const providerSelectors = provider === "outlook"
      ? [
        '[data-testid="From"]',
        '[aria-label^="From" i]',
        '[aria-label*="From:" i]',
      ]
      : provider === "yahoo"
        ? [
          '[data-test-id="message-from"]',
          '.sender-email',
          'a[href^="mailto:"]',
        ]
        : provider === "gmail"
          ? [
            '.gD[email]',
            'span.gD[email]',
            '.gE .gD',
            'span[email]',
            '[data-hovercard-id*="@"]',
            'a[href^="mailto:"]',
          ]
          : [];

    for (const selector of providerSelectors) {
      const nodes = header.querySelectorAll(selector);
      for (const node of nodes) {
        if (!(node instanceof HTMLElement)) {
          continue;
        }

        const title = node.getAttribute("title") ?? "";
        const text = node.textContent ?? "";
        const href = node instanceof HTMLAnchorElement ? node.getAttribute("href") ?? "" : "";
        const emailAttr = node.getAttribute("email") ?? "";
        const hovercard = node.getAttribute("data-hovercard-id") ?? "";
        const candidate = emailAttr.includes("@")
          ? emailAttr
          : (href.startsWith("mailto:")
            ? href.replace(/^mailto:/i, "")
            : (hovercard.includes("@")
              ? hovercard
              : (title.includes("@") ? title : text)));
        const match = candidate.match(/[\w.+-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
        if (match) {
          return resolveSenderEmailAddress(match[0].trim());
        }
      }
    }

    const openContainer = findOpenMessageContainer();
    if (openContainer instanceof HTMLElement) {
      const emailNodes = openContainer.querySelectorAll(
        ".gD[email], [email], .gD[email], [data-hovercard-id]"
      );
      for (const node of emailNodes) {
        if (!(node instanceof HTMLElement)) {
          continue;
        }

        if (!header.contains(node) && !node.classList.contains("gD") && !node.hasAttribute("email")) {
          continue;
        }

        const hovercard = node.getAttribute("data-hovercard-id") ?? "";
        const emailAttr = node.getAttribute("email") ?? "";
        const email = emailAttr.includes("@")
          ? emailAttr
          : (hovercard.includes("@") ? hovercard : emailAttr);

        if (email.includes("@")) {
          return resolveSenderEmailAddress(email.trim());
        }
      }
    }

    const parsedFromHeader = parseSenderEmailFromHeaderText(header.innerText ?? "");
    if (parsedFromHeader) {
      return resolveSenderEmailAddress(parsedFromHeader);
    }

    return null;
  }

  /** Extracts a domain-like token from text. */
  function domainFromText(text) {
    const match = String(text ?? "").match(/([a-z0-9-]+\.)+[a-z]{2,}/i);
    return match ? match[0].toLowerCase() : null;
  }

  /** Returns true when hostname is an IPv4 literal. */
  function isIPv4Host(hostname) {
    return /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname);
  }

  /** Returns true when a hostname uses punycode (IDN homograph risk). */
  function isPunycodeHost(hostname) {
    return /(^|\.)xn--/i.test(String(hostname ?? ""));
  }

  /** Strips common confusable Unicode so domains can be compared safely. */
  function foldHomographText(value) {
    return String(value ?? "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[il1|]/g, "l")
      .replace(/[0o]/g, "o");
  }

  /** Rough registrable domain (e.g. outlook.live.com → live.com is wrong but provedorway.com → provedorway.com). */
  function registrableDomain(hostname) {
    const host = String(hostname ?? "").replace(/^www\./, "").toLowerCase();
    const parts = host.split(".").filter(Boolean);
    if (parts.length <= 2) {
      return host;
    }
    return parts.slice(-2).join(".");
  }

  /** True when two hostnames belong to the same site (sender vs link destination). */
  function domainsAlign(hostnameA, hostnameB) {
    if (!hostnameA || !hostnameB) {
      return false;
    }
    const a = registrableDomain(hostnameA);
    const b = registrableDomain(hostnameB);
    return a === b || hostnameA.endsWith(`.${b}`) || hostnameB.endsWith(`.${a}`);
  }

  const MICROSOFT_FAMILY = [
    "microsoft.com",
    "live.com",
    "hotmail.com",
    "outlook.com",
    "office.com",
    "office365.com",
    "microsoftonline.com",
  ];

  const PERSONAL_MAILBOX_DOMAINS = new Set([
    "gmail.com",
    "googlemail.com",
    "hotmail.com",
    "outlook.com",
    "live.com",
    "yahoo.com",
    "icloud.com",
    "me.com",
    "proton.me",
    "protonmail.com",
  ]);

  const CTA_LABEL_PATTERN =
    /^(confirm(\s+account)?|verify(\s+(your\s+)?account)?|update(\s+(your\s+)?account)?|click\s+here|sign\s+in|reset\s+password|unlock(\s+account)?|account\s+update)/i;

  const NOISE_ONLY_FLAG_IDS = new Set([
    "missing-profile-icon",
    "blurry-graphics",
    "insecure-http",
    "mismatch-return",
    "urgent-timer",
    "excessive-links",
    "remote-images",
    "hidden-link",
  ]);

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

  const KNOWN_BRAND_LABELS = [
    "microsoft",
    "google",
    "apple",
    "amazon",
    "paypal",
    "netflix",
    "spotify",
    "facebook",
    "instagram",
    "linkedin",
    "dropbox",
    "docusign",
    "chase",
    "wellsfargo",
    "bankofamerica",
  ];

  const DANGEROUS_ATTACHMENT_EXTENSIONS = [
    "app",
    "pkg",
    "dmg",
    "command",
    "scpt",
    "exe",
    "scr",
    "bat",
    "js",
    "vbs",
    "cmd",
    "msi",
    "apk",
    "jar",
    "wsf",
    "ps1",
  ];

  const APP_PLATFORM_DOMAINS = new Set([
    "apps.apple.com",
    "itunes.apple.com",
    "play.google.com",
    "apps.microsoft.com",
    "market.android.com",
  ]);

  const FOOTER_PLATFORM_LABEL_PATTERN =
    /^(ios|android|ipad|iphone|mac|windows|download|get the app|spotify for|available for|google play|app store)/i;

  /** True for normal newsletter footer links (App Store / Play Store / same brand). */
  function isBenignPlatformLink(label, host, senderDomain) {
    const normalizedHost = String(host ?? "").replace(/^www\./, "").toLowerCase();
    const registrable = registrableDomain(normalizedHost);

    if (APP_PLATFORM_DOMAINS.has(normalizedHost) || APP_PLATFORM_DOMAINS.has(registrable)) {
      return FOOTER_PLATFORM_LABEL_PATTERN.test(String(label ?? "").trim())
        || Boolean(senderDomain && domainsAlign(normalizedHost, senderDomain));
    }

    if (senderDomain && domainsAlign(normalizedHost, senderDomain)) {
      return true;
    }

    return false;
  }

  /** True when a link destination is worth flagging as hidden/suspicious. */
  function isSuspiciousLinkDestination(label, host, senderDomain) {
    if (!senderDomain) {
      return true;
    }

    if (isBenignPlatformLink(label, host, senderDomain)) {
      return false;
    }

    return !domainsAlign(host, senderDomain);
  }

  /** Returns true when a hostname belongs to a common URL shortener service. */
  function isUrlShortener(hostname) {
    const host = String(hostname ?? "").replace(/^www\./, "").toLowerCase();
    const registrable = registrableDomain(host);
    return URL_SHORTENER_DOMAINS.has(host) || URL_SHORTENER_DOMAINS.has(registrable);
  }

  /** Returns true when the hostname TLD is commonly abused in phishing. */
  function isSuspiciousTld(hostname) {
    const host = String(hostname ?? "").replace(/^www\./, "").toLowerCase();
    const parts = host.split(".").filter(Boolean);
    if (parts.length < 2) {
      return false;
    }
    const tld = parts[parts.length - 1];
    return SUSPICIOUS_TLDS.has(tld);
  }

  /** Simple edit distance for typosquat checks against known brand labels. */
  function editDistance(a, b) {
    const left = String(a ?? "");
    const right = String(b ?? "");
    const rows = left.length + 1;
    const cols = right.length + 1;
    const matrix = Array.from({ length: rows }, () => Array(cols).fill(0));

    for (let row = 0; row < rows; row += 1) {
      matrix[row][0] = row;
    }
    for (let col = 0; col < cols; col += 1) {
      matrix[0][col] = col;
    }

    for (let row = 1; row < rows; row += 1) {
      for (let col = 1; col < cols; col += 1) {
        const cost = left[row - 1] === right[col - 1] ? 0 : 1;
        matrix[row][col] = Math.min(
          matrix[row - 1][col] + 1,
          matrix[row][col - 1] + 1,
          matrix[row - 1][col - 1] + cost
        );
      }
    }

    return matrix[rows - 1][cols - 1];
  }

  /** Returns a known brand label when a hostname looks like a one-character misspell. */
  function detectTyposquatBrand(hostname) {
    const label = registrableDomain(hostname).split(".")[0].toLowerCase();
    if (label.length < 4) {
      return null;
    }

    for (const brand of KNOWN_BRAND_LABELS) {
      if (label === brand) {
        return null;
      }
      const distance = editDistance(label, brand);
      if (distance === 1 || (distance === 2 && label.length >= 6)) {
        return brand;
      }
    }

    return null;
  }

  /** Reads the visible sender display name from the webmail header. */
  function extractSenderDisplayName() {
    const header = findSenderHeaderOnly();
    if (!(header instanceof HTMLElement)) {
      return null;
    }

    const namedNode = header.querySelector('[name], .gD[email], span[email], [data-testid="From"]');
    if (namedNode instanceof HTMLElement) {
      const explicitName = namedNode.getAttribute("name")?.trim();
      if (explicitName) {
        return explicitName;
      }

      const email = namedNode.getAttribute("email") ?? "";
      const text = namedNode.textContent?.trim() ?? "";
      if (text && email && text.toLowerCase() !== email.toLowerCase()) {
        return text.replace(email, "").replace(/[<>]/g, "").trim() || null;
      }
    }

    const fromLine = header.innerText?.match(/\bfrom[:\s]+([^\n]+)/i)?.[1] ?? "";
    const withoutEmail = fromLine.replace(/<[^>]+>/g, "").replace(/[\w.+-]+@[^\s>]+/g, "").trim();
    return withoutEmail || null;
  }

  /** Detects a brand token embedded in the sender display name. */
  function brandTokenFromDisplayName(displayName) {
    const normalized = String(displayName ?? "").toLowerCase();
    if (!normalized) {
      return null;
    }

    for (const brand of KNOWN_BRAND_LABELS) {
      if (normalized.includes(brand)) {
        return brand;
      }
    }

    const domain = domainFromText(displayName);
    return domain ? registrableDomain(domain).split(".")[0] : null;
  }

  /** Builds positive/negative evidence lines for the expandable report panel. */
  function buildRiskReport(flags, senderDomain, threadContext = null, threadBlocks = null) {
    const headerRegion = findSenderHeaderOnly();
    let score = 0;
    /** @type {Array<{ text: string, points: string, positive: boolean }>} */
    const evidence = [];

    for (const flag of flags) {
      const points = FLAG_SCORE[flag.id] ?? 8;
      score += points;
    }

    if (threadContext?.groupedEvidence?.length) {
      evidence.push(...threadContext.groupedEvidence);
    } else {
      for (const flag of flags) {
        const points = FLAG_SCORE[flag.id] ?? 8;
        const detail = flag.detail ? ` (${flag.detail})` : "";
        evidence.push({
          text: `${FLAG_COPY[flag.id] ?? flag.id}${detail}`,
          points: `+${points}`,
          positive: true,
        });
      }
    }

    for (const relief of collectAuthenticationRelief(headerRegion, senderDomain)) {
      score += relief.points;
      evidence.push({
        text: relief.text,
        points: `${relief.points}`,
        positive: false,
      });
    }

    score = Math.max(0, Math.min(100, score));

    let finalSeverity = "low";
    if (score >= 56) {
      finalSeverity = "high";
    } else if (score >= 26) {
      finalSeverity = "medium";
    }

    const blocks = threadBlocks ?? findThreadMessageBlocks();
    let linkCount = 0;
    if (blocks.length > 0) {
      for (const block of blocks) {
        linkCount += analyzeMessageLinks(block.root).httpLinks.length;
      }
    } else {
      linkCount = analyzeMessageLinks(findMessageRoot() ?? document.body).httpLinks.length;
    }

    return {
      score,
      evidence,
      finalSeverity,
      linkCount,
      threadMessageCount: threadContext?.threadMessageCount ?? Math.max(blocks.length, 1),
      uniqueRiskCount: threadContext?.uniqueRiskCount ?? flags.length,
      collapsedMentionCount: threadContext?.collapsedMentionCount ?? 0,
      isStackedThread: threadContext?.isStackedThread ?? blocks.length > 1,
    };
  }

  /** Reads Gmail/Outlook authentication hints that can lower the report score. */
  function collectAuthenticationRelief(headerRegion, senderDomain) {
    /** @type {Array<{ id: string, text: string, points: number }>} */
    const relief = [];
    if (!(headerRegion instanceof HTMLElement) || !senderDomain) {
      return relief;
    }

    const text = `${headerRegion.innerText ?? ""}\n${headerRegion.getAttribute("title") ?? ""}`;
    const signedBy = text.match(/signed[- ]?by[:\s]+([a-z0-9.-]+\.[a-z]{2,})/i)?.[1];
    const mailedBy = text.match(/mailed[- ]?by[:\s]+([a-z0-9.-]+\.[a-z]{2,})/i)?.[1];

    if (signedBy && domainsAlign(signedBy, senderDomain)) {
      relief.push({
        id: "auth-signed-by",
        text: `Signed-by aligns with sender (${signedBy})`,
        points: RELIEF_SCORE["auth-signed-by"],
      });
    }

    if (mailedBy && domainsAlign(mailedBy, senderDomain)) {
      relief.push({
        id: "auth-mailed-by",
        text: `Mailed-by aligns with sender (${mailedBy})`,
        points: RELIEF_SCORE["auth-mailed-by"],
      });
    }

    return relief;
  }

  /** Finds the webmail chrome around the sender row (avatar, verified badge). */
  function findSenderChromeRegion() {
    const provider = webmailProvider();
    if (provider === "outlook") {
      const outlookChromeSelectors = [
        "#ReadingPaneContainer",
        '[data-app-section="ReadingPane"]',
        '[role="main"] [data-testid="messageHeader"]',
        '[role="main"] [aria-label*="Message header" i]',
        '[role="main"] [class*="ReadingPane"]',
      ];
      for (const selector of outlookChromeSelectors) {
        const node = document.querySelector(selector);
        if (node instanceof HTMLElement) {
          return node;
        }
      }
    }

    return findHeaderRegion();
  }

  /** True when the webmail UI shows a sender avatar or verified/authenticated badge. */
  function hasSenderIdentityChrome() {
    const regions = [];
    const seen = new Set();
    for (const region of [findSenderChromeRegion(), findHeaderRegion(), findOpenMessageContainer()]) {
      if (!(region instanceof HTMLElement) || seen.has(region)) {
        continue;
      }
      seen.add(region);
      regions.push(region);
    }

    const avatarSelectors = [
      '[data-testid="PersonaCoin"]',
      '[data-testid="persona-coin"]',
      'img[data-testid="SenderImage"]',
      'img[aria-label*="profile" i]',
      'img[aria-label*="avatar" i]',
      'img[aria-label*="sender" i]',
      'img[src*="googleusercontent.com"]',
      'img[src*="avatar"]',
      '[class*="persona" i] img',
      '[class*="Persona" i] img',
      '.gA img',
      '[data-test-id="sender-avatar"]',
      '[data-testid="sender-avatar"]',
      '[aria-label*="verified" i]',
      '[title*="verified" i]',
      '[data-icon-name="VerifiedBrand"]',
      '[data-icon-name="SkypeCircleCheck"]',
      '[data-icon-name="Verified"]',
      '[class*="verified" i] svg',
      '[class*="authenticated" i]',
    ];

    for (const region of regions) {
      if (avatarSelectors.some((selector) => region.querySelector(selector))) {
        return true;
      }

      const text = region.innerText ?? "";
      if (/verified\s+sender|authenticat|official\s+sender|sender\s+verified/i.test(text)) {
        return true;
      }
    }

    return false;
  }

  /** Collects http(s) links in the message body for brand-alignment checks. */
  function analyzeMessageLinks(messageRoot) {
    if (!(messageRoot instanceof HTMLElement)) {
      return { httpLinks: [], uniqueLinkDomains: [] };
    }

    const httpLinks = [...messageRoot.querySelectorAll("a[href]")].filter((anchor) => {
      if (!(anchor instanceof HTMLAnchorElement)) {
        return false;
      }
      try {
        const protocol = new URL(anchor.href).protocol;
        return protocol === "http:" || protocol === "https:";
      } catch {
        return false;
      }
    });

    const linkRegistrableDomains = httpLinks.map((anchor) => {
      try {
        return registrableDomain(new URL(anchor.href).hostname);
      } catch {
        return null;
      }
    }).filter(Boolean);

    return {
      httpLinks,
      uniqueLinkDomains: [...new Set(linkRegistrableDomains)],
    };
  }

  /** True when most links belong to the same brand as the sender/header. */
  function linksLookBrandLegitimate(senderDomain, messageRoot) {
    const { httpLinks, uniqueLinkDomains } = analyzeMessageLinks(messageRoot);
    if (httpLinks.length === 0) {
      return false;
    }

    const headerText = `${findSenderHeaderOnly()?.innerText ?? ""}\n${findHeaderRegion()?.innerText ?? ""}`;

    if (uniqueLinkDomains.length === 1) {
      const unifiedLinkDomain = uniqueLinkDomains[0];
      const brandStem = unifiedLinkDomain.split(".")[0];
      if (brandStem.length >= 4) {
        const brandPattern = new RegExp(
          `\\b${brandStem.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`,
          "i"
        );
        if (brandPattern.test(headerText)) {
          return true;
        }
      }
    }

    if (!senderDomain) {
      return false;
    }

    const alignedWithSender = httpLinks.filter((anchor) => {
      try {
        return domainsAlign(new URL(anchor.href).hostname, senderDomain);
      } catch {
        return false;
      }
    }).length;

    if (alignedWithSender === httpLinks.length) {
      return true;
    }

    if (uniqueLinkDomains.length === 1) {
      const unifiedLinkDomain = uniqueLinkDomains[0];
      if (domainsAlign(unifiedLinkDomain, senderDomain)) {
        return true;
      }
    }

    return alignedWithSender / httpLinks.length >= 0.85;
  }

  /** Highest severity label across a set of flags. */
  function severityForFlags(flags) {
    let highest = "low";
    for (const flag of flags) {
      const level = FLAG_SEVERITY[flag.id] ?? "low";
      if ((SEVERITY_RANK[level] ?? 0) > (SEVERITY_RANK[highest] ?? 0)) {
        highest = level;
      }
    }
    return highest;
  }

  /** Sends warning/dismiss events to the background worker for Mac Security Activity. */
  function logDynamicShieldEvent(event, senderDomain, flagSummary) {
    safeRuntimeSendMessage({
      type: "DYNAMIC_SHIELD_EVENT",
      event,
      senderDomain: senderDomain ?? null,
      flagSummary: flagSummary ?? null,
    });
  }

  /** Builds a short flag summary for Security Activity (first three labels). */
  function summarizeFlags(flags) {
    return flags
      .slice(0, 3)
      .map((flag) => FLAG_COPY[flag.id] ?? flag.id)
      .join(", ");
  }

  /** Returns true when text looks like a URL or domain label. */
  function looksLikeLinkLabel(text) {
    const normalized = String(text ?? "").trim().toLowerCase();
    if (!normalized || normalized.length > 120) {
      return false;
    }
    return (
      normalized.includes("http://")
      || normalized.includes("https://")
      || /^([a-z0-9-]+\.)+[a-z]{2,}$/i.test(normalized)
      || /^www\./i.test(normalized)
    );
  }

  /** Scans visible header/sender area for phishing header flags. */
  function scanHeaders(headerRegion) {
    /** @type {Array<{ id: string, detail?: string }>} */
    const flags = [];
    const text = headerRegion.innerText ?? "";

    if (/\bvia\s+[a-z0-9.-]+\.[a-z]{2,}\b/i.test(text) && /\bfrom\b/i.test(text)) {
      flags.push({ id: "mismatch-return" });
    }

    const fromLine = text.match(/\bfrom[:\s]+([^\n]+)/i)?.[1] ?? "";
    const replyLine = text.match(/\breply[- ]to[:\s]+([^\n]+)/i)?.[1] ?? "";
    if (fromLine && replyLine) {
      const fromDomain = domainFromText(fromLine);
      const replyDomain = domainFromText(replyLine);
      if (fromDomain && replyDomain && fromDomain !== replyDomain) {
        flags.push({ id: "mismatch-return", detail: `${fromDomain} vs ${replyDomain}` });
      }
    }

    const avatarSelectors = [
      'img[aria-label*="profile" i]',
      'img[aria-label*="avatar" i]',
      'img[src*="googleusercontent.com"]',
      'img[src*="avatar"]',
      '.gA img',
      '[data-test-id="sender-avatar"]',
      '[data-testid="sender-avatar"]',
      '[data-testid="PersonaCoin"]',
      '[data-testid="persona-coin"]',
      'img[data-testid="SenderImage"]',
      '[class*="persona" i] img',
      '[aria-label*="verified" i]',
      '[data-icon-name="VerifiedBrand"]',
      '[data-icon-name="SkypeCircleCheck"]',
    ];
    const hasAvatar = avatarSelectors.some((selector) => headerRegion.querySelector(selector))
      || hasSenderIdentityChrome();
    const hasBimiHint = /verified|brand|official|authenticat/i.test(text);
    if (!hasAvatar && !hasBimiHint && /[@]/.test(text)) {
      flags.push({ id: "missing-profile-icon" });
    }

    const warningPatterns = [
      /external sender/i,
      /be careful with this message/i,
      /this message might be dangerous/i,
      /report phishing/i,
      /suspicious email/i,
      /spam/i,
      /unverified sender/i,
      /security warning/i,
    ];
    if (warningPatterns.some((pattern) => pattern.test(text))) {
      flags.push({ id: "provider-warning" });
    }

    return flags;
  }

  /** Flags when the visible sender name implies a different brand than the real sender domain. */
  function scanSenderDisplayMismatch(headerRegion, senderDomain) {
    /** @type {Array<{ id: string, detail?: string }>} */
    const flags = [];
    if (!senderDomain) {
      return flags;
    }

    const displayName = extractSenderDisplayName();
    const brandToken = brandTokenFromDisplayName(displayName);
    if (!brandToken) {
      return flags;
    }

    const senderLabel = registrableDomain(senderDomain).split(".")[0];
    if (brandToken === senderLabel) {
      return flags;
    }

    if (!domainsAlign(`${brandToken}.com`, senderDomain)) {
      flags.push({
        id: "sender-display-mismatch",
        detail: `${displayName ?? brandToken} vs ${senderDomain}`,
      });
    }

    return flags;
  }

  /** Scans link volume and remote image usage patterns. */
  function scanMessageComposition(root) {
    /** @type {Array<{ id: string, detail?: string }>} */
    const flags = [];
    const httpLinks = [...root.querySelectorAll("a[href]")].filter((anchor) => {
      if (!(anchor instanceof HTMLAnchorElement)) {
        return false;
      }
      try {
        const protocol = new URL(anchor.href).protocol;
        return protocol === "http:" || protocol === "https:";
      } catch {
        return false;
      }
    });

    if (httpLinks.length >= 25) {
      flags.push({ id: "excessive-links", detail: `${httpLinks.length} links` });
    }

    const remoteImages = [...root.querySelectorAll("img[src]")].filter((img) => {
      if (!(img instanceof HTMLImageElement)) {
        return false;
      }
      return /^https?:\/\//i.test(img.src);
    });

    if (remoteImages.length >= 8) {
      flags.push({ id: "remote-images", detail: `${remoteImages.length} remote images` });
    }

    return flags;
  }

  /** Scans links in the message for hover-preview style risks. */
  function scanLinks(root, senderDomain) {
    /** @type {Array<{ id: string, detail?: string }>} */
    const flags = [];
    const seen = new Set();

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

      if (url.protocol === "http:") {
        const onSenderBrand = Boolean(senderDomain && domainsAlign(url.hostname, senderDomain));
        if (!onSenderBrand) {
          const key = `insecure-http:${url.href}`;
          if (!seen.has(key)) {
            seen.add(key);
            flags.push({ id: "insecure-http", detail: url.href });
          }
        }
      }

      if (isIPv4Host(url.hostname)) {
        const key = `ip-address:${url.hostname}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "ip-address", detail: url.hostname });
        }
      }

      if (isPunycodeHost(url.hostname)) {
        const key = `homograph-link:${url.hostname}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "homograph-link", detail: url.hostname });
        }
      }

      if (isUrlShortener(url.hostname)) {
        const key = `url-shortener:${url.hostname}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "url-shortener", detail: url.hostname });
        }
      }

      if (isSuspiciousTld(url.hostname)) {
        const key = `suspicious-tld:${url.hostname}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "suspicious-tld", detail: url.hostname });
        }
      }

      const typosquatBrand = detectTyposquatBrand(url.hostname);
      if (typosquatBrand) {
        const key = `typosquat-domain:${url.hostname}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "typosquat-domain", detail: `${url.hostname} ≈ ${typosquatBrand}` });
        }
      }

      const label = anchor.textContent.trim();
      const host = url.hostname.replace(/^www\./, "");
      const labelDomain = domainFromText(label);
      if (labelDomain && looksLikeLinkLabel(label)) {
        const normalizedLabel = labelDomain.replace(/^www\./, "");
        if (host && normalizedLabel && !host.endsWith(normalizedLabel) && !normalizedLabel.endsWith(host)) {
          const key = `mismatched-destination:${labelDomain}->${host}`;
          if (!seen.has(key)) {
            seen.add(key);
            flags.push({ id: "mismatched-destination", detail: `${labelDomain} → ${host}` });
          }
        } else if (
          host
          && normalizedLabel
          && foldHomographText(host) === foldHomographText(normalizedLabel)
          && host !== normalizedLabel
        ) {
          const key = `homograph-link:${labelDomain}->${host}`;
          if (!seen.has(key)) {
            seen.add(key);
            flags.push({ id: "homograph-link", detail: `${labelDomain} → ${host}` });
          }
        }
      } else if (
        label
        && label.length <= 80
        && senderDomain
        && isSuspiciousLinkDestination(label, host, senderDomain)
        && !label.toLowerCase().includes(host.toLowerCase())
        && !CTA_LABEL_PATTERN.test(label)
      ) {
        const key = `hidden-link:${label.slice(0, 24)}->${host}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({ id: "hidden-link", detail: `${label.slice(0, 32)} → ${host}` });
        }
      }
    });

    return flags;
  }

  /** Scans action buttons and brand-themed scams (CTA text ≠ link domain). */
  function scanActionLinks(root, senderDomain) {
    /** @type {Array<{ id: string, detail?: string }>} */
    const flags = [];
    const seen = new Set();
    const impersonatesMicrosoft = messageImpersonatesMicrosoft(root);
    const senderReg = senderDomain ? registrableDomain(senderDomain) : null;

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
      const label = anchor.textContent.trim();
      const isShortCTA = label.length > 0 && label.length <= 48 && CTA_LABEL_PATTERN.test(label);

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
        if (!onMicrosoftFamily && !shouldSkipBrandImpersonationLink(host)) {
          const key = `brand-impersonation:microsoft→${host}`;
          if (!seen.has(key)) {
            seen.add(key);
            flags.push({ id: "brand-impersonation", detail: `Microsoft branding → ${host}` });
          }
        }
      }

      if (senderReg && isShortCTA && !domainsAlign(host, senderDomain)) {
        const linkReg = registrableDomain(host);
        const key = `cta-domain-mismatch:${senderReg}→${linkReg}`;
        if (!seen.has(key)) {
          seen.add(key);
          flags.push({
            id: "cta-domain-mismatch",
            detail: `Sender ${senderReg} → button ${linkReg}`,
          });
        }
      }
    });

    return flags;
  }

  /**
   * Hides noisy banners when the sender domain matches real link destinations
   * (legitimate transactional mail like OpenRouter welcome).
   */
  function filterBenignTransactionalFlags(flags, senderDomain, messageRoot) {
    if (!senderDomain || flags.length === 0) {
      return flags;
    }

    const { httpLinks, uniqueLinkDomains } = analyzeMessageLinks(messageRoot);

    if (httpLinks.length === 0) {
      return flags;
    }

    const allLinksShareOneDomain = uniqueLinkDomains.length === 1;
    const unifiedLinkDomain = allLinksShareOneDomain ? uniqueLinkDomains[0] : null;

    const allLinksMatchSender = httpLinks.every((anchor) => {
      try {
        return domainsAlign(new URL(anchor.href).hostname, senderDomain);
      } catch {
        return false;
      }
    });

    const headerText = `${findSenderChromeRegion()?.innerText ?? ""}\n${findHeaderRegion()?.innerText ?? ""}`;
    const displayMatchesLinkBrand = Boolean(
      unifiedLinkDomain
      && unifiedLinkDomain.split(".")[0].length >= 4
      && new RegExp(
        `\\b${unifiedLinkDomain.split(".")[0].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`,
        "i"
      ).test(headerText)
    );

    const looksLikeLegitimateTransactionalMail =
      allLinksMatchSender
      || (allLinksShareOneDomain && displayMatchesLinkBrand)
      || linksLookBrandLegitimate(senderDomain, messageRoot);

    if (!looksLikeLegitimateTransactionalMail) {
      return flags;
    }

    const hasHighSeverity = flags.some((flag) => (FLAG_SEVERITY[flag.id] ?? "low") === "high");
    if (hasHighSeverity) {
      return flags;
    }

    return [];
  }

  /**
   * Suppresses banners that only contain soft/noisy heuristics on brand-aligned mail
   * (e.g. Spotify marketing with http tracking links on the same domain).
   */
  function filterNoiseOnlyWarnings(flags, senderDomain, messageRoot) {
    if (flags.length === 0) {
      return flags;
    }

    const hasHighSeverity = flags.some((flag) => (FLAG_SEVERITY[flag.id] ?? "low") === "high");
    if (hasHighSeverity) {
      return flags;
    }

    const onlyNoiseFlags = flags.every((flag) => NOISE_ONLY_FLAG_IDS.has(flag.id));
    if (onlyNoiseFlags && linksLookBrandLegitimate(senderDomain, messageRoot)) {
      return [];
    }

    return flags;
  }

  /** Scans visual urgency/layout signals in the message body. */
  function scanVisuals(root) {
    /** @type {Array<{ id: string, detail?: string }>} */
    const flags = [];
    const text = root.innerText ?? "";

    const urgentPatterns = [
      /expires?\s+in\s+\d+\s*(minute|hour|second|day)/i,
      /\bact\s+now\b/i,
      /\bwithin\s+\d+\s*(minute|hour)\b/i,
      /\bcountdown\b/i,
      /\burgent\b/i,
      /\bfinal\s+warning\b/i,
    ];
    const hasUrgentText = urgentPatterns.some((pattern) => pattern.test(text));
    const hasUrgentStyle = [...root.querySelectorAll("*")].some((element) => {
      if (!(element instanceof HTMLElement)) {
        return false;
      }
      const style = window.getComputedStyle(element);
      const bg = style.backgroundColor;
      const rgb = bg.match(/\d+/g);
      if (!rgb || rgb.length < 3) {
        return false;
      }
      const [r, g, b] = rgb.map(Number);
      const isRedBlock = r > 170 && g < 90 && b < 90 && element.clientHeight > 18;
      const animated = style.animationName && style.animationName !== "none";
      return isRedBlock || (animated && /countdown|timer/i.test(element.className));
    });

    if (hasUrgentText || hasUrgentStyle) {
      flags.push({ id: "urgent-timer" });
    }

    let blurryCount = 0;
    let brokenCount = 0;
    root.querySelectorAll("img").forEach((img) => {
      if (!(img instanceof HTMLImageElement)) {
        return;
      }
      if (img.complete && img.naturalWidth === 0) {
        brokenCount += 1;
        return;
      }

      const displayWidth = img.clientWidth || img.width;
      const displayHeight = img.clientHeight || img.height;
      const isTinyIcon = displayWidth > 0 && displayWidth < 48 && displayHeight > 0 && displayHeight < 48;
      if (isTinyIcon) {
        return;
      }

      if (
        img.naturalWidth > 80
        && displayWidth > 80
        && img.naturalWidth < displayWidth * 0.32
      ) {
        blurryCount += 1;
      }
    });

    if (blurryCount >= 2) {
      flags.push({ id: "blurry-graphics", detail: `${blurryCount} image(s)` });
    }
    if (brokenCount > 0) {
      flags.push({ id: "broken-layout", detail: `${brokenCount} broken image(s)` });
    }

    const unsubscribe = [...root.querySelectorAll("a[href]")].find((anchor) =>
      /unsubscribe/i.test(anchor.textContent ?? "")
    );
    if (unsubscribe instanceof HTMLAnchorElement) {
      try {
        const unsubUrl = new URL(unsubscribe.href);
        const suspicious =
          /login|signin|sign-in|account|verify|password|auth/i.test(unsubUrl.pathname)
          || unsubUrl.protocol === "http:";
        if (suspicious) {
          flags.push({ id: "fake-unsubscribe", detail: unsubUrl.hostname });
        }
      } catch {
        flags.push({ id: "fake-unsubscribe" });
      }
    } else if (/unsubscribe/i.test(text) === false && /marketing|newsletter|offer/i.test(text)) {
      flags.push({ id: "fake-unsubscribe", detail: "Missing unsubscribe option" });
    }

    return flags;
  }

  /** Collects unique attachment basenames and their Gmail/UI source labels under a scan root. */
  function collectAttachmentBasenames(root) {
    /** @type {Map<string, { displayName: string, sources: Set<string> }>} */
    const basenames = new Map();

    const recordLabel = (label) => {
      const trimmed = String(label ?? "").trim();
      if (!trimmed) {
        return;
      }

      const clean = sanitizeAttachmentFilename(trimmed);
      if (!clean) {
        return;
      }

      const key = clean.toLowerCase();
      if (!basenames.has(key)) {
        basenames.set(key, { displayName: clean, sources: new Set() });
      }

      basenames.get(key).sources.add(trimmed);
    };

    if (webmailProvider() === "gmail") {
      root.querySelectorAll(".aZo").forEach((chip) => {
        if (!(chip instanceof HTMLElement)) {
          return;
        }

        recordLabel(`${chip.getAttribute("aria-label") ?? ""} ${chip.textContent ?? ""}`.trim());
        chip.querySelectorAll('[aria-label*="attachment" i], [data-tooltip*="attachment" i], button, a').forEach((node) => {
          if (node instanceof HTMLElement) {
            recordLabel(`${node.getAttribute("aria-label") ?? ""} ${node.getAttribute("data-tooltip") ?? ""} ${node.textContent ?? ""}`.trim());
          }
        });
      });
    }

    const selectors = [
      '[aria-label*="attachment" i]',
      '[data-tooltip*="attachment" i]',
      ".aZo",
      '[data-test-id*="attachment"]',
      ".attachment",
    ];

    selectors.forEach((selector) => {
      root.querySelectorAll(selector).forEach((node) => {
        if (!(node instanceof HTMLElement)) {
          return;
        }

        recordLabel(`${node.getAttribute("aria-label") ?? ""} ${node.getAttribute("data-tooltip") ?? ""} ${node.textContent ?? ""}`.trim());
      });
    });

    return basenames;
  }

  /** Scans attachment chips for dangerous naming patterns. */
  function scanAttachments(root) {
    if (webmailProvider() === "proton" && IS_TOP_FRAME) {
      return scanProtonAttachments();
    }

    const basenames = collectAttachmentBasenames(root);
    const flags = buildAttachmentFlagsFromNames(
      [...basenames.values()].map((entry) => entry.displayName)
    );

    return flags.map((flag) => {
      const key = sanitizeAttachmentFilename(flag.detail ?? "").toLowerCase();
      const entry = basenames.get(key);
      if (!entry) {
        return flag;
      }

      return {
        ...flag,
        detail: entry.displayName,
        _sourceDetail: [...entry.sources][0] ?? entry.displayName,
        _attachmentSourceCount: entry.sources.size,
      };
    });
  }

  /** Stable id for the currently open email (for temporary dismiss). */
  function getMessageIdentity() {
    const root = findMessageRoot();
    if (root) {
      const messageEl = root.closest("[data-message-id], [data-legacy-message-id]") ?? root;
      const messageId = messageEl.getAttribute?.("data-message-id")
        || messageEl.getAttribute?.("data-legacy-message-id");
      if (messageId) {
        return `msg:${messageId}`;
      }
    }

    if (webmailProvider() === "proton") {
      const urlIdentity = getProtonMessageIdentityFromTop();
      if (urlIdentity) {
        return urlIdentity;
      }

      const contentFrame = document.querySelector('iframe[data-testid="content-iframe"]');
      const subject = contentFrame?.getAttribute("data-subject")
        ?? document.querySelector('[data-testid="encrypted-subject-banner"]')?.textContent
        ?? "";
      const fromEmail = extractProtonSenderEmail()
        ?? document.querySelector('[data-testid="recipients:sender"]')?.textContent
        ?? "";
      const protonKey = `${String(subject).trim()}|${String(fromEmail).trim()}`.trim();
      if (protonKey.length > 2 && protonKey !== "|") {
        return `proton:${protonKey.slice(0, 200)}`;
      }

      const protonHeader = document.querySelector(
        '[data-testid^="message-header-expanded"], [data-testid^="message-header-collapsed"]'
      );
      if (protonHeader instanceof HTMLElement) {
        const headerKey = String(protonHeader.innerText ?? "").trim();
        if (headerKey.length > 2) {
          return `proton:${headerKey.slice(0, 200)}`;
        }
      }
    }

    if (root) {
      const bodyKey = String(root.innerText ?? "").trim();
      if (bodyKey.length > 20) {
        return `body:${bodyKey.slice(0, 200)}`;
      }

      const header = findHeaderRegion();
      return `fallback:${String(header?.innerText ?? "").slice(0, 200)}`;
    }

    return null;
  }

  /** Extracts sender domain from the open message header. */
  function extractSenderDomain() {
    const structuredEmail = extractSenderEmailAddress();
    if (structuredEmail) {
      const fromEmail = normalizeSenderDomain(structuredEmail);
      if (fromEmail && !PERSONAL_MAILBOX_DOMAINS.has(fromEmail)) {
        return fromEmail;
      }
    }

    const header = findSenderHeaderOnly();
    const parsedFromHeader = parseSenderEmailFromHeaderText(header?.innerText ?? "");
    if (parsedFromHeader) {
      const parsedDomain = normalizeSenderDomain(parsedFromHeader);
      if (parsedDomain && !PERSONAL_MAILBOX_DOMAINS.has(parsedDomain)) {
        return parsedDomain;
      }
    }

    const outlookFrom = extractOutlookFromEmail();
    if (outlookFrom) {
      const outlookDomain = normalizeSenderDomain(outlookFrom);
      if (outlookDomain && !PERSONAL_MAILBOX_DOMAINS.has(outlookDomain)) {
        return outlookDomain;
      }
    }

    return null;
  }

  /** Skips webmail UI / provider links when evaluating brand impersonation. */
  function shouldSkipBrandImpersonationLink(host) {
    const normalized = String(host ?? "").replace(/^www\./, "").toLowerCase();
    const currentHost = location.hostname.replace(/^www\./, "").toLowerCase();

    if (!normalized) {
      return true;
    }

    if (normalized === currentHost || normalized.endsWith(`.${currentHost}`)) {
      return true;
    }

    if (currentHost === "mail.google.com" && (normalized === "google.com" || normalized.endsWith(".google.com"))) {
      return true;
    }

    if (
      (currentHost.includes("outlook") || currentHost.includes("live.com"))
      && MICROSOFT_FAMILY.some((domain) => normalized === domain || normalized.endsWith(`.${domain}`))
    ) {
      return true;
    }

    if (
      (currentHost === "mail.proton.me" || currentHost === "mail.protonmail.com")
      && (normalized.endsWith(".proton.me") || normalized.endsWith(".protonmail.com"))
    ) {
      return true;
    }

    return false;
  }

  /** True when the message body mimics Microsoft branding (not just your @hotmail address). */
  function messageImpersonatesMicrosoft(root) {
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
    if (brandPhrases.some((pattern) => pattern.test(bodyText))) {
      return true;
    }

    return [...root.querySelectorAll("img")].some((img) => {
      if (!(img instanceof HTMLImageElement)) {
        return false;
      }
      const alt = (img.alt ?? "").toLowerCase();
      const src = (img.src ?? "").toLowerCase();
      return alt.includes("microsoft") || src.includes("microsoft");
    });
  }

  /** Returns true when the sender domain is on the trusted list. */
  function isSenderTrusted() {
    const senderDomain = extractSenderDomain();
    const normalized = normalizeSenderDomain(senderDomain);
    return Boolean(normalized && trustedDomains.includes(normalized));
  }

  /** Persists a trusted sender domain locally until Mac list sync completes. */
  function addTrustedDomain(domain) {
    const normalized = normalizeSenderDomain(domain);
    if (!normalized) {
      return;
    }

    if (!trustedDomains.includes(normalized)) {
      trustedDomains = [...trustedDomains, normalized].sort();
      if (isExtensionContextValid()) {
        try {
          browserAPI.storage.local.set({
            [TRUSTED_DOMAINS_KEY]: trustedDomains,
          });
        } catch {
          // Ignore after an extension reload.
        }
      }
    }
  }

  /** Marks the sender as trusted locally and asks the background worker to sync to the Mac app. */
  function applyLocalTrust(domain) {
    const normalized = normalizeSenderDomain(domain);
    if (!normalized) {
      hideBanner();
      return null;
    }

    addTrustedDomain(normalized);

    safeRuntimeSendMessage({
      type: "DYNAMIC_SHIELD_TRUST",
      senderDomain: normalized,
    });

    hideBanner();
    return normalized;
  }

  /** Pulls the Mac trusted-sender list and updates in-memory cache before scans. */
  let macTrustSyncPromise = null;
  let lastMacTrustSyncAt = 0;
  let lastScannedMessageIdentity = null;
  const MAC_TRUST_SYNC_COOLDOWN_MS = 4000;

  function applyTrustedDomainsFromSyncResponse(response) {
    const domains = response?.ok ? response.result?.trustedSenderDomains : null;
    if (!Array.isArray(domains)) {
      return;
    }

    trustedDomains = domains
      .map((domain) => String(domain ?? "").trim().toLowerCase().replace(/^@/, ""))
      .filter(Boolean)
      .sort();
  }

  function syncTrustedDomainsFromMac(force = false) {
    if (!isExtensionContextValid()) {
      stopProtonScanHeartbeat();
      return Promise.resolve();
    }

    const now = Date.now();
    if (!force && macTrustSyncPromise) {
      return macTrustSyncPromise;
    }
    if (!force && now - lastMacTrustSyncAt < MAC_TRUST_SYNC_COOLDOWN_MS) {
      return Promise.resolve();
    }

    macTrustSyncPromise = new Promise((resolve) => {
      safeRuntimeSendMessage({ type: "SYNC_DYNAMIC_SHIELD_TRUSTED" }, (response) => {
        lastMacTrustSyncAt = Date.now();
        macTrustSyncPromise = null;
        applyTrustedDomainsFromSyncResponse(response);
        resolve();
      });
    });

    return macTrustSyncPromise;
  }

  /** Forces a Mac trusted-sender pull (used on page load and when Safari regains focus). */
  function requestMacTrustedListSync() {
    lastMacTrustSyncAt = 0;
    return syncTrustedDomainsFromMac(true);
  }

  /** Hides the banner for the current message view only. */
  function dismissBannerForCurrentMessage() {
    const identity = getMessageIdentity();
    dismissedMessageId = identity;
    clearActiveWarningState(identity);
    logDynamicShieldEvent("dismissed", extractSenderDomain(), null);
    hideBanner();
  }

  /** True when banner should stay hidden for this message or sender. */
  function shouldSkipBanner() {
    const identity = getMessageIdentity();
    if (identity && dismissedMessageId === identity) {
      return true;
    }

    return isSenderTrusted();
  }

  /** Deduplicates flags by id + detail. */
  function dedupeFlags(flags) {
    const seen = new Set();
    return flags.map((flag) => {
      if (
        flag.id === "double-extension"
        || flag.id === "dangerous-attachment"
        || flag.id === "message-attachments"
      ) {
        const detail = sanitizeAttachmentFilename(flag.detail ?? "");
        return detail ? { ...flag, detail } : flag;
      }
      return flag;
    }).filter((flag) => {
      let key = `${flag.id}:${flag.detail ?? ""}`;
      if (
        flag.id === "double-extension"
        || flag.id === "dangerous-attachment"
        || flag.id === "message-attachments"
      ) {
        key = `${flag.id}:${sanitizeAttachmentFilename(flag.detail ?? "").toLowerCase()}`;
      }
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  }

  /** True when the user is browsing Spam/Junk — provider already flagged these messages. */
  function isViewingSpamOrJunkFolder() {
    const provider = webmailProvider();

    if (provider === "gmail") {
      const selectedFolder = document.querySelector(
        '.aDP .nZ.aAy[aria-selected="true"], .aDP .aKz[aria-selected="true"]'
      );
      const folderLabel = `${selectedFolder?.getAttribute("data-tooltip") ?? ""} ${selectedFolder?.textContent ?? ""}`;
      if (/spam|søppel|junk/i.test(folderLabel)) {
        return true;
      }
    }

    if (provider === "outlook") {
      const selectedFolder = document.querySelector(
        '[role="treeitem"][aria-selected="true"], [role="option"][aria-selected="true"]'
      );
      const folderLabel = `${selectedFolder?.getAttribute("title") ?? ""} ${selectedFolder?.textContent ?? ""}`;
      if (/junk|spam|søppelpost/i.test(folderLabel)) {
        return true;
      }
    }

    return /spam|junk email|søppelpost/i.test(document.title);
  }

  /** Runs all local heuristics on the open message. */
  function scanOpenMessage() {
    if (!mailShieldEnabled || !isWebmailHost()) {
      return [];
    }

    if (isViewingSpamOrJunkFolder()) {
      return [];
    }

    if (isSenderTrusted()) {
      return [];
    }

    const threadBlocks = findThreadMessageBlocks();
    const protonAttachmentRoot = webmailProvider() === "proton" ? findProtonAttachmentRoot() : null;

    if (threadBlocks.length === 0) {
      if (protonAttachmentRoot instanceof HTMLElement) {
        return scanProtonPartialMessage();
      }
      consumeProtonIframeBridge();
      return mergeProtonScanFlags([]);
    }

    const headerRegion = findSenderHeaderOnly();
    const senderDomain = extractSenderDomain();
    /** @type {Array<{ id: string, detail?: string, _threadMessage?: number, _sourceDetail?: string }>} */
    const rawFlags = [];

    for (const block of threadBlocks) {
      const messageRoot = block.root;
      const attachmentRoot = findAttachmentScanRoot(messageRoot) ?? messageRoot;
      const threadMessage = block.index + 1;

      if (block.index === 0) {
        rawFlags.push(...tagFlagsForThread(scanHeaders(headerRegion), threadMessage));
        rawFlags.push(...tagFlagsForThread(scanSenderDisplayMismatch(headerRegion, senderDomain), threadMessage));
      }

      const attachmentFlags = webmailProvider() === "proton" && IS_TOP_FRAME && block.index === 0
        ? scanProtonAttachments()
        : scanAttachments(attachmentRoot);
      rawFlags.push(...tagFlagsForThread(scanLinks(messageRoot, senderDomain), threadMessage));
      rawFlags.push(...tagFlagsForThread(scanActionLinks(messageRoot, senderDomain), threadMessage));
      rawFlags.push(...tagFlagsForThread(scanVisuals(messageRoot), threadMessage));
      rawFlags.push(...tagFlagsForThread(attachmentFlags, threadMessage));

      if (block.index === 0) {
        rawFlags.push(...tagFlagsForThread(scanMessageComposition(messageRoot), threadMessage));
      }
    }

    return filterNoiseOnlyWarnings(
      mergeProtonScanFlags(
        filterBenignTransactionalFlags(rawFlags, senderDomain, threadBlocks[0]?.root ?? null)
      ),
      senderDomain,
      threadBlocks[0]?.root ?? null
    );
  }

  /** Partial scan used when Proton attachments exist but the HTML body iframe is still loading. */
  function scanProtonPartialMessage() {
    return mergeProtonScanFlags(scanProtonAttachments());
  }

  class MailShieldBanner {
    constructor() {
      this.host = document.createElement("div");
      this.host.id = "dynamickey-mail-shield";
      this.shadow = this.host.attachShadow({ mode: "closed" });
      this.onDismiss = null;
      this.onTrust = null;
      this.shadow.innerHTML = `
        <style>
          .banner {
            position: fixed;
            top: 12px;
            right: 12px;
            z-index: 2147483646;
            width: min(380px, calc(100vw - 24px));
            padding: 14px 16px 12px;
            border-radius: 18px;
            border: 1px solid var(--banner-border, rgba(255, 107, 107, 0.32));
            background: rgba(15, 23, 42, 0.84);
            backdrop-filter: blur(24px) saturate(160%);
            -webkit-backdrop-filter: blur(24px) saturate(160%);
            color: #f8fafc;
            font: 12px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            box-shadow:
              inset 0 1px 0 rgba(255, 255, 255, 0.1),
              0 16px 40px rgba(15, 23, 42, 0.28);
          }
          .banner[data-severity="high"] {
            --banner-border: rgba(248, 113, 113, 0.55);
            --title-color: #fecaca;
            --badge-bg: rgba(248, 113, 113, 0.22);
            --badge-color: #fecaca;
          }
          .banner[data-severity="medium"] {
            --banner-border: rgba(251, 146, 60, 0.5);
            --title-color: #fed7aa;
            --badge-bg: rgba(251, 146, 60, 0.2);
            --badge-color: #fdba74;
          }
          .banner[data-severity="low"] {
            --banner-border: rgba(250, 204, 21, 0.45);
            --title-color: #fde68a;
            --badge-bg: rgba(250, 204, 21, 0.18);
            --badge-color: #fde68a;
          }
          .title-row {
            display: flex;
            align-items: flex-start;
            gap: 10px;
            margin-bottom: 10px;
          }
          .window-btn {
            margin-left: auto;
            flex-shrink: 0;
            width: 28px;
            height: 28px;
            padding: 0;
            border-radius: 8px;
            border: 1px solid rgba(255, 255, 255, 0.2);
            background: rgba(255, 255, 255, 0.08);
            color: rgba(248, 250, 252, 0.88);
            cursor: pointer;
            font-size: 18px;
            line-height: 1;
            font-weight: 500;
          }
          .window-btn:hover {
            background: rgba(255, 255, 255, 0.14);
          }
          .minimized-chip {
            display: none;
            margin: 2px 0 0;
            font-size: 11px;
            color: rgba(248, 250, 252, 0.72);
          }
          .banner[data-minimized="true"] {
            top: auto;
            bottom: 16px;
            width: auto;
            max-width: min(320px, calc(100vw - 24px));
            padding: 10px 12px;
            cursor: pointer;
          }
          .banner[data-minimized="true"] .title-row {
            margin-bottom: 0;
            align-items: center;
          }
          .banner[data-minimized="true"] .logo {
            width: 20px;
            height: 20px;
          }
          .banner[data-minimized="true"] .title {
            font-size: 12px;
          }
          .banner[data-minimized="true"] .subtitle,
          .banner[data-minimized="true"] .severity-badge {
            display: none;
          }
          .banner[data-minimized="true"] .minimized-chip {
            display: block;
          }
          .banner-body[hidden] {
            display: none;
          }
          .logo {
            width: 24px;
            height: 24px;
            border-radius: 7px;
            flex-shrink: 0;
          }
          .title-text {
            min-width: 0;
          }
          .title {
            margin: 0;
            font-size: 14px;
            font-weight: 700;
            color: var(--title-color, #fecaca);
            letter-spacing: 0.01em;
          }
          .severity-badge {
            display: inline-block;
            margin-top: 4px;
            padding: 2px 8px;
            border-radius: 999px;
            font-size: 10px;
            font-weight: 700;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            background: var(--badge-bg, rgba(248, 113, 113, 0.22));
            color: var(--badge-color, #fecaca);
          }
          .subtitle {
            margin: 2px 0 0;
            font-size: 11px;
            color: rgba(248, 250, 252, 0.62);
          }
          .thread-scope {
            margin: 0 0 10px;
            font-size: 11px;
            font-weight: 600;
            color: rgba(248, 250, 252, 0.78);
          }
          ul {
            margin: 0;
            padding-left: 18px;
          }
          li {
            margin: 0 0 6px;
          }
          .detail {
            color: rgba(248, 250, 252, 0.72);
          }
          .hover {
            margin-top: 8px;
            padding-top: 8px;
            border-top: 1px solid rgba(255, 255, 255, 0.12);
            color: rgba(248, 250, 252, 0.82);
            font-size: 11px;
          }
          .actions {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
            margin-top: 12px;
            flex-wrap: wrap;
          }
          .btn {
            min-width: 112px;
            padding: 8px 14px;
            border-radius: 12px;
            border: 1px solid rgba(255, 255, 255, 0.24);
            font-size: 12px;
            font-weight: 600;
            cursor: pointer;
            background: rgba(255, 255, 255, 0.08);
            color: #f8fafc;
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            transition: transform 0.12s ease, opacity 0.12s ease;
          }
          .btn:hover {
            transform: translateY(-1px);
          }
          .btn.subtle {
            background: rgba(255, 255, 255, 0.06);
            color: rgba(248, 250, 252, 0.78);
          }
          .btn.primary-safe {
            background: rgba(52, 211, 153, 0.22);
            border-color: rgba(52, 211, 153, 0.45);
            color: #6ee7b7;
          }
          .btn.dismiss {
            min-width: auto;
            padding: 8px 12px;
            background: transparent;
            border: 1px dashed rgba(255, 255, 255, 0.24);
            color: rgba(248, 250, 252, 0.62);
            font-weight: 500;
          }
          .btn.dismiss:hover {
            color: rgba(248, 250, 252, 0.88);
            border-color: rgba(255, 255, 255, 0.36);
          }
          .btn.report {
            min-width: auto;
            background: rgba(96, 165, 250, 0.16);
            border-color: rgba(96, 165, 250, 0.35);
            color: #bfdbfe;
          }
          .report-panel {
            margin-top: 10px;
            padding-top: 10px;
            border-top: 1px solid rgba(255, 255, 255, 0.12);
          }
          .report-panel[hidden] {
            display: none;
          }
          .score-row {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: 12px;
            margin-bottom: 8px;
          }
          .score-label {
            font-size: 11px;
            color: rgba(248, 250, 252, 0.68);
            text-transform: uppercase;
            letter-spacing: 0.05em;
          }
          .score-value {
            font-size: 22px;
            font-weight: 800;
            color: #f8fafc;
          }
          .score-meta {
            font-size: 11px;
            color: rgba(248, 250, 252, 0.58);
            margin-bottom: 8px;
            line-height: 1.5;
            white-space: pre-line;
          }
          .evidence-title {
            margin: 0 0 6px;
            font-size: 11px;
            font-weight: 700;
            color: rgba(248, 250, 252, 0.78);
            text-transform: uppercase;
            letter-spacing: 0.04em;
          }
          .evidence-list {
            margin: 0;
            padding: 0;
            list-style: none;
          }
          .evidence-list li {
            display: flex;
            align-items: flex-start;
            justify-content: space-between;
            gap: 10px;
            margin: 0 0 6px;
            font-size: 11px;
          }
          .evidence-points {
            flex-shrink: 0;
            font-weight: 700;
          }
          .evidence-points.positive {
            color: #fca5a5;
          }
          .evidence-points.negative {
            color: #6ee7b7;
          }
          .final-risk {
            margin-top: 8px;
            font-size: 12px;
            font-weight: 700;
            color: #fde68a;
          }
        </style>
        <div class="banner" hidden>
          <header class="title-row">
            <img class="logo" data-role="logo" alt="" width="24" height="24" />
            <div class="title-text">
              <p class="title">DynamicShield Warning</p>
              <p class="subtitle" data-role="subtitle">Suspicious patterns detected in this email</p>
              <span class="severity-badge" data-role="severity" hidden></span>
              <p class="minimized-chip" data-role="minimized-chip" hidden></p>
            </div>
            <button type="button" class="window-btn" data-action="toggle-minimize" aria-label="Minimize warning" title="Minimize">−</button>
          </header>
          <div class="banner-body" data-role="banner-body">
          <p class="thread-scope" data-role="thread-scope" hidden></p>
          <ul data-role="list"></ul>
          <p class="hover" data-role="hover" hidden></p>
          <section class="report-panel" data-role="report" hidden>
            <div class="score-row">
              <span class="score-label">Risk Score</span>
              <span class="score-value" data-role="score">0 / 100</span>
            </div>
            <p class="score-meta" data-role="score-meta"></p>
            <p class="evidence-title">Evidence</p>
            <ul class="evidence-list" data-role="evidence"></ul>
            <p class="final-risk" data-role="final-risk"></p>
          </section>
          <div class="actions">
            <button type="button" class="btn report" data-action="report">View Report</button>
            <button type="button" class="btn dismiss" data-action="dismiss" title="Hide this warning for the current email only">Hide for Now</button>
            <button type="button" class="btn primary-safe" data-action="trust">Mark Sender Safe</button>
          </div>
          </div>
        </div>
      `;
      this.bannerEl = this.shadow.querySelector(".banner");
      this.listEl = this.shadow.querySelector('[data-role="list"]');
      this.hoverEl = this.shadow.querySelector('[data-role="hover"]');
      this.severityEl = this.shadow.querySelector('[data-role="severity"]');
      this.subtitleEl = this.shadow.querySelector('[data-role="subtitle"]');
      this.threadScopeEl = this.shadow.querySelector('[data-role="thread-scope"]');
      this.bannerBodyEl = this.shadow.querySelector('[data-role="banner-body"]');
      this.minimizedChipEl = this.shadow.querySelector('[data-role="minimized-chip"]');
      this.minimizeButtonEl = this.shadow.querySelector('[data-action="toggle-minimize"]');
      this.logoEl = this.shadow.querySelector('[data-role="logo"]');
      this.reportEl = this.shadow.querySelector('[data-role="report"]');
      this.scoreEl = this.shadow.querySelector('[data-role="score"]');
      this.scoreMetaEl = this.shadow.querySelector('[data-role="score-meta"]');
      this.evidenceEl = this.shadow.querySelector('[data-role="evidence"]');
      this.finalRiskEl = this.shadow.querySelector('[data-role="final-risk"]');
      this.reportButtonEl = this.shadow.querySelector('[data-action="report"]');
      this.logoEl.src = EXTENSION_ICON_URL;
      this.reportExpanded = false;
      this.isMinimized = false;
      this.lastReport = null;
      this.lastFlagCount = 0;
      this.lastSeverityLabel = "Risk detected";

      this.reportButtonEl.addEventListener("click", () => {
        this.reportExpanded = !this.reportExpanded;
        this.reportEl.hidden = !this.reportExpanded;
        this.reportButtonEl.textContent = this.reportExpanded ? "Hide Report" : "View Report";
      });

      this.minimizeButtonEl.addEventListener("click", (event) => {
        event.stopPropagation();
        this.setMinimized(!this.isMinimized);
      });

      this.bannerEl.addEventListener("click", (event) => {
        if (!this.isMinimized) {
          return;
        }
        if (event.target instanceof HTMLElement && event.target.closest('[data-action="toggle-minimize"]')) {
          return;
        }
        this.setMinimized(false);
      });

      this.shadow.querySelector('[data-action="dismiss"]').addEventListener("click", () => {
        this.onDismiss?.();
      });
      this.shadow.querySelector('[data-action="trust"]').addEventListener("click", () => {
        this.onTrust?.();
      });
    }

    /** Updates the one-line summary shown while the warning banner is minimized. */
    updateMinimizedChip() {
      if (!(this.minimizedChipEl instanceof HTMLElement)) {
        return;
      }

      const riskLabel = `${this.lastFlagCount} unique risk${this.lastFlagCount === 1 ? "" : "s"}`;
      this.minimizedChipEl.textContent = `${this.lastSeverityLabel} · ${riskLabel} · tap to expand`;
    }

    /** Collapses or expands the warning banner without dismissing it for this email. */
    setMinimized(minimized) {
      this.isMinimized = minimized;
      this.bannerEl.dataset.minimized = minimized ? "true" : "false";
      this.minimizeButtonEl.textContent = minimized ? "+" : "−";
      this.minimizeButtonEl.setAttribute(
        "aria-label",
        minimized ? "Expand warning" : "Minimize warning"
      );
      this.minimizeButtonEl.title = minimized ? "Expand" : "Minimize";
      this.bannerBodyEl.hidden = minimized;
      this.minimizedChipEl.hidden = !minimized;

      if (minimized) {
        this.reportEl.hidden = true;
        this.reportExpanded = false;
        this.reportButtonEl.textContent = "View Report";
        this.updateMinimizedChip();
      }
    }

    /** Resets transient banner UI when the user opens a different email. */
    resetForNewMessage() {
      this.setMinimized(false);
    }

    renderReport(report) {
      if (!report) {
        this.reportEl.hidden = true;
        return;
      }

      this.lastReport = report;
      this.scoreEl.textContent = `${report.score} / 100`;
      const metaLines = [];
      metaLines.push(
        report.threadMessageCount === 1
          ? "Scanned 1 message"
          : `Scanned ${report.threadMessageCount} messages in this thread`
      );
      const summaryParts = [
        `${report.uniqueRiskCount} unique risk${report.uniqueRiskCount === 1 ? "" : "s"}`,
      ];
      if (report.collapsedMentionCount > 0) {
        summaryParts.push(
          `${report.collapsedMentionCount} duplicate mention${report.collapsedMentionCount === 1 ? "" : "s"} collapsed`
        );
      }
      metaLines.push(summaryParts.join(" · "));
      metaLines.push(
        `${report.linkCount} link${report.linkCount === 1 ? "" : "s"} scanned in this ${report.isStackedThread ? "thread" : "message"}`
      );
      this.scoreMetaEl.textContent = metaLines.join("\n");
      this.evidenceEl.innerHTML = report.evidence
        .map((item) => {
          const pointClass = item.positive ? "positive" : "negative";
          return `<li><span>${item.text}</span><span class="evidence-points ${pointClass}">${item.points}</span></li>`;
        })
        .join("");
      this.finalRiskEl.textContent = `Final Risk: ${(SEVERITY_COPY[report.finalSeverity] ?? report.finalSeverity).toUpperCase()}`;

      if (!this.reportExpanded) {
        this.reportEl.hidden = true;
      }
    }

    show(flags, severity = "medium", report = null) {
      if (!flags.length) {
        this.hide();
        return;
      }

      const resolvedSeverity = report?.finalSeverity ?? severity ?? "medium";
      this.bannerEl.dataset.severity = resolvedSeverity;
      this.lastSeverityLabel = SEVERITY_COPY[resolvedSeverity] ?? "Risk detected";
      this.lastFlagCount = flags.length;
      this.severityEl.textContent = this.lastSeverityLabel;
      this.severityEl.hidden = false;
      const messageCount = report?.threadMessageCount ?? 1;
      const scopeLabel = messageCount === 1
        ? "1 message scanned"
        : `${messageCount} messages scanned`;
      const patternLabel = `${flags.length} unique risk${flags.length === 1 ? "" : "s"}`;
      this.subtitleEl.textContent = report
        ? `v${SHIELD_BUILD_VERSION} · Risk score ${report.score}/100 · ${scopeLabel} · ${patternLabel}`
        : `v${SHIELD_BUILD_VERSION} · ${flags.length} suspicious pattern${flags.length === 1 ? "" : "s"} detected`;

      if (report && this.threadScopeEl) {
        this.threadScopeEl.textContent = formatThreadScanScope(report);
        this.threadScopeEl.hidden = false;
      } else if (this.threadScopeEl) {
        this.threadScopeEl.textContent = "";
        this.threadScopeEl.hidden = true;
      }

      this.listEl.innerHTML = flags
        .map((flag) => {
          const label = FLAG_COPY[flag.id] ?? flag.id;
          const level = FLAG_SEVERITY[flag.id] ?? "low";
          const points = FLAG_SCORE[flag.id];
          const scoreHint = points ? ` <span class="detail">(+${points})</span>` : "";
          const detail = flag.detail ? ` <span class="detail">(${flag.detail})</span>` : "";
          const threadHint = flag.threadNote ? ` <span class="detail">[${flag.threadNote}]</span>` : "";
          return `<li data-severity="${level}">${label}${scoreHint}${detail}${threadHint}</li>`;
        })
        .join("");

      this.renderReport(report);
      this.updateMinimizedChip();

      if (!this.host.isConnected) {
        document.documentElement.appendChild(this.host);
      }
      this.bannerEl.hidden = false;
    }

    hide() {
      if (this.host.isConnected) {
        this.bannerEl.hidden = true;
        this.hoverEl.hidden = true;
        this.reportEl.hidden = true;
        if (this.threadScopeEl) {
          this.threadScopeEl.hidden = true;
        }
        this.setMinimized(false);
        this.reportExpanded = false;
        this.reportButtonEl.textContent = "View Report";
      }
    }

    setHoverPreview(text) {
      if (!text) {
        this.hoverEl.hidden = true;
        this.hoverEl.textContent = "";
        return;
      }
      this.hoverEl.hidden = false;
      this.hoverEl.textContent = text;
    }
  }

  const banner = new MailShieldBanner();

  banner.onDismiss = dismissBannerForCurrentMessage;
  banner.onTrust = () => {
    const email = extractSenderEmailAddress();
    const domain = extractSenderDomain() || normalizeSenderDomain(email);
    applyLocalTrust(domain || email);
  };

  function hideBanner() {
    banner.hide();
  }

  function hideLinkHover() {
    banner.setHoverPreview("");
  }

  /** True when scan results include body/link phishing signals from the mail iframe. */
  function protonScanHasBodyRisks(flags) {
    const bodyRiskIds = new Set([
      "suspicious-admin-path",
      "brand-impersonation",
      "cta-domain-mismatch",
      "mismatched-destination",
      "hidden-link",
      "homograph-link",
      "url-shortener",
      "typosquat-domain",
      "fake-unsubscribe",
      "insecure-http",
      "ip-address",
      "suspicious-tld",
    ]);
    return flags.some((flag) => bodyRiskIds.has(flag.id));
  }

  /** Merges top-frame and iframe Proton scan results before presenting warnings. */
  function mergeProtonScanFlags(flags) {
    if (webmailProvider() !== "proton" || !IS_TOP_FRAME) {
      return dedupeFlags(flags);
    }

    consumeProtonIframeBridge();

    const currentIdentity = getProtonBridgeIdentity() ?? getMessageIdentity();
    if (
      currentIdentity
      && pendingProtonIframeIdentity
      && currentIdentity !== pendingProtonIframeIdentity
    ) {
      pendingProtonIframeFlags = [];
      pendingProtonIframeIdentity = null;
    }

    return appendProtonAttachmentNotice(dedupeFlags([
      ...flags,
      ...pendingProtonIframeFlags,
    ]));
  }

  /** Re-scans Proton messages while the content iframe finishes rendering HTML mail. */
  async function rescanProtonWhenReady(initialFlags) {
    if (webmailProvider() !== "proton" || !IS_TOP_FRAME) {
      return initialFlags;
    }

    if (!hasProtonMessageOpen()) {
      return mergeProtonScanFlags(initialFlags);
    }

    if (canReadProtonIframeDirectly()) {
      return mergeProtonScanFlags(scanOpenMessage());
    }

    let resolvedFlags = mergeProtonScanFlags(initialFlags);
    await pullProtonIframeFlagsFromScripting();
    resolvedFlags = mergeProtonScanFlags(scanOpenMessage());
    if (protonScanHasBodyRisks(resolvedFlags)) {
      return resolvedFlags;
    }

    const delaySchedule = [250, 600, 1200, 2200, 3500, 5000, 7000];
    for (const delayMs of delaySchedule) {
      await new Promise((resolve) => {
        window.setTimeout(resolve, delayMs);
      });
      await pullProtonIframeFlagsFromScripting();
      watchProtonMessageFrames();
      resolvedFlags = mergeProtonScanFlags(scanOpenMessage());
      if (protonScanHasBodyRisks(resolvedFlags)) {
        break;
      }
    }

    return resolvedFlags;
  }

  /** Shows the warning banner and caches it for sticky re-display on Proton. */
  function presentWarning(identity, resolvedFlags) {
    const threadBlocks = findThreadMessageBlocks();
    const threadMessageCount = countThreadMessagesScanned(threadBlocks);
    const preparedFlags = resolvedFlags.map(normalizeFlagForThreadGrouping);
    const threadContext = consolidateThreadFlags(preparedFlags, threadMessageCount);
    const report = buildRiskReport(
      threadContext.scoringFlags,
      extractSenderDomain(),
      threadContext,
      threadBlocks
    );
    const severity = report.finalSeverity || severityForFlags(threadContext.scoringFlags);
    const resolvedIdentity = identity ?? getMessageIdentity();

    if (resolvedIdentity) {
      activeWarningState = {
        identity: resolvedIdentity,
        flags: threadContext.displayFlags,
        severity,
        report,
      };
    }

    banner.show(threadContext.displayFlags, severity, report);

    if (resolvedIdentity && !loggedWarningMessageIds.has(resolvedIdentity)) {
      loggedWarningMessageIds.add(resolvedIdentity);
      logDynamicShieldEvent(
        "warning_shown",
        extractSenderDomain(),
        summarizeFlags(threadContext.displayFlags)
      );
    }
  }

  function scheduleScan() {
    if (scanTimer !== null) {
      window.clearTimeout(scanTimer);
    }
    scanTimer = window.setTimeout(() => {
      scanTimer = null;
      const generation = ++scanGeneration;

      void (async () => {
        if (!isExtensionContextValid()) {
          stopProtonScanHeartbeat();
          return;
        }

        const identity = webmailProvider() === "proton"
          ? (getProtonBridgeIdentity() ?? getMessageIdentity())
          : getMessageIdentity();
        const hasOpenMessage = webmailProvider() === "proton" && IS_TOP_FRAME
          ? hasProtonMessageOpen()
          : Boolean(findMessageRoot() || (webmailProvider() === "proton" && findProtonAttachmentRoot()));

        if (!identity && !hasOpenMessage) {
          dismissedMessageId = null;
          lastScannedMessageIdentity = null;
          pendingProtonIframeFlags = [];
          pendingProtonIframeIdentity = null;
          hideBanner();
          return;
        }

        const openedNewMessage = identity !== lastScannedMessageIdentity;
        if (openedNewMessage) {
          if (identity && activeWarningState?.identity !== identity) {
            clearActiveWarningState();
          }
          banner.resetForNewMessage();
          lastScannedMessageIdentity = identity;
        }

        if (generation !== scanGeneration) {
          return;
        }

        await syncTrustedDomainsFromMac(openedNewMessage);

        if (generation !== scanGeneration) {
          return;
        }

        if (identity && dismissedMessageId && dismissedMessageId !== identity) {
          dismissedMessageId = null;
        }

        if (shouldSkipBanner()) {
          hideBanner();
          return;
        }

        if (webmailProvider() === "proton" && IS_TOP_FRAME && !canReadProtonIframeDirectly()) {
          await pullProtonIframeFlagsFromScripting();
          if (identity && getProtonBridgeIdentity() !== identity && getMessageIdentity() !== identity) {
            return;
          }
        }

        const stickyBeforeScan = getStickyWarningForIdentity(identity);
        if (stickyBeforeScan) {
          banner.show(stickyBeforeScan.flags, stickyBeforeScan.severity, stickyBeforeScan.report);
        }

        const initialFlags = filterNoiseOnlyWarnings(
          mergeProtonScanFlags(scanOpenMessage()),
          extractSenderDomain(),
          findMessageRoot()
        );
        if (initialFlags.length > 0) {
          presentWarning(identity, initialFlags);
        }

        const resolvedFlags = filterNoiseOnlyWarnings(
          await rescanProtonWhenReady(initialFlags),
          extractSenderDomain(),
          findMessageRoot()
        );

        if (identity && getProtonBridgeIdentity() !== identity && getMessageIdentity() !== identity) {
          return;
        }

        if (resolvedFlags.length > 0) {
          presentWarning(identity, resolvedFlags);
          return;
        }

        const sticky = getStickyWarningForIdentity(identity);
        if (sticky) {
          banner.show(sticky.flags, sticky.severity, sticky.report);
          return;
        }

        hideBanner();
      })();
    }, 350);
  }

  function getLinkHoverRoot() {
    return findOpenMessageContainer() ?? findMessageRoot() ?? document.querySelector('[role="main"]');
  }

  function attachLinkHoverPreview(root) {
    if (!(root instanceof HTMLElement)) {
      return;
    }
    if (linkHoverHosts.has(root)) {
      return;
    }
    linkHoverHosts.add(root);
    let hoverClearTimer = null;

    root.addEventListener("mouseover", (event) => {
      if (hoverClearTimer !== null) {
        window.clearTimeout(hoverClearTimer);
        hoverClearTimer = null;
      }

      const target = event.target;
      if (!(target instanceof Element)) {
        return;
      }

      const anchor = target.closest("a[href]");
      if (!(anchor instanceof HTMLAnchorElement) || !anchor.href || anchor.href.startsWith("mailto:")) {
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

      const label = anchor.textContent.trim();
      const labelDomain = domainFromText(label);
      const host = url.hostname.replace(/^www\./, "");
      const parts = [`Destination: ${url.href}`];

      if (url.protocol === "http:") {
        parts.push("Insecure HTTP");
      }
      if (isIPv4Host(url.hostname)) {
        parts.push("Uses IP address");
      }
      if (isPunycodeHost(url.hostname)) {
        parts.push("Uses punycode domain");
      }
      if (labelDomain && looksLikeLinkLabel(label)) {
        const normalizedLabel = labelDomain.replace(/^www\./, "");
        if (host && normalizedLabel && !host.endsWith(normalizedLabel) && !normalizedLabel.endsWith(host)) {
          parts.push(`Text says ${normalizedLabel}`);
        }
      }

      banner.setHoverPreview(parts.join(" · "));
    }, true);

    root.addEventListener("mouseout", (event) => {
      const target = event.target;
      if (!(target instanceof Element)) {
        return;
      }

      const fromAnchor = target.closest("a[href]");
      const related = event.relatedTarget;
      const toAnchor = related instanceof Element ? related.closest("a[href]") : null;
      if (fromAnchor && toAnchor === fromAnchor) {
        return;
      }

      hoverClearTimer = window.setTimeout(() => {
        hideLinkHover();
        hoverClearTimer = null;
      }, 90);
    }, true);
  }

  /** Attaches hover previews inside Gmail/Outlook HTML email iframes when accessible. */
  function attachLinkHoverToMessageFrames() {
    const frameRoots = [
      findMessageRoot(),
      findOpenMessageContainer(),
      document.querySelector('[role="main"]'),
    ].filter((node) => node instanceof HTMLElement);

    for (const root of frameRoots) {
      root.querySelectorAll("iframe").forEach((frame) => {
        if (!(frame instanceof HTMLIFrameElement)) {
          return;
        }

        const bindFrame = () => {
          try {
            const frameBody = frame.contentDocument?.body;
            if (frameBody instanceof HTMLElement) {
              attachLinkHoverPreview(frameBody);
            }
          } catch {
            // Cross-origin frames cannot be inspected.
          }
        };

        bindFrame();
        frame.addEventListener("load", bindFrame);
      });
    }
  }

  function refreshLinkHoverListeners() {
    const roots = new Set(
      [
        getLinkHoverRoot(),
        findMessageRoot(),
        findOpenMessageContainer(),
      ].filter((node) => node instanceof HTMLElement)
    );

    if (webmailProvider() === "proton") {
      document.querySelectorAll(
        'iframe[data-testid="content-iframe"], iframe[title*="Email content" i], iframe[sandbox]'
      ).forEach((frame) => {
        if (!(frame instanceof HTMLIFrameElement)) {
          return;
        }

        const bindFrame = () => {
          try {
            const frameDocument = frame.contentDocument;
            const protonRoot = frameDocument?.getElementById("proton-root");
            const frameBody = protonRoot instanceof HTMLElement
              ? protonRoot
              : frameDocument?.body;
            if (frameBody instanceof HTMLElement) {
              roots.add(frameBody);
              attachLinkHoverPreview(frameBody);
            }
          } catch {
            // Ignore cross-origin frames.
          }
        };

        bindFrame();
        frame.addEventListener("load", bindFrame);
      });
    }

    for (const root of roots) {
      attachLinkHoverPreview(root);
    }

    attachLinkHoverToMessageFrames();
  }

  /** Notifies the Proton top frame when rendered mail appears inside the content iframe. */
  function initProtonMessageFrameWatcher() {
    let lastPayload = "";

    const notifyTopFrame = () => {
      if (!mailShieldEnabled) {
        return;
      }

      const protonRoot = document.getElementById("proton-root");
      if (!(protonRoot instanceof HTMLElement) || protonRoot.textContent.trim().length === 0) {
        return;
      }

      const localFlags = dedupeFlags([
        ...scanLinks(protonRoot, null),
        ...scanActionLinks(protonRoot, null),
        ...scanVisuals(protonRoot),
      ]);
      const payload = JSON.stringify(localFlags);
      if (payload === lastPayload) {
        return;
      }

      lastPayload = payload;
      publishProtonIframeFlags(localFlags);
    };

    notifyTopFrame();

    const observer = new MutationObserver(notifyTopFrame);
    observer.observe(document.documentElement, { childList: true, subtree: true });
    window.setInterval(notifyTopFrame, 2000);
  }

  /** Keeps polling Proton on Chromium browsers where iframe handoff can be delayed. */
  function stopProtonScanHeartbeat() {
    if (protonScanHeartbeat !== null) {
      window.clearInterval(protonScanHeartbeat);
      protonScanHeartbeat = null;
    }
  }

  function startProtonScanHeartbeat() {
    if (protonScanHeartbeat || webmailProvider() !== "proton" || !IS_TOP_FRAME) {
      return;
    }

    protonScanHeartbeat = window.setInterval(() => {
      if (!isExtensionContextValid()) {
        stopProtonScanHeartbeat();
        return;
      }

      if (document.visibilityState !== "visible" || !mailShieldEnabled) {
        return;
      }

      consumeProtonIframeBridge();
      if (!hasProtonMessageOpen()) {
        return;
      }

      void pullProtonIframeFlagsFromScripting();
      scheduleScan();
    }, 2500);
  }

  function bootstrap() {
    if (!IS_TOP_FRAME && isProtonMailContentFrame()) {
      initProtonMessageFrameWatcher();
      return;
    }

    if (!isWebmailHost()) {
      return;
    }

    if (webmailProvider() === "proton" && !IS_TOP_FRAME) {
      initProtonMessageFrameWatcher();
      return;
    }

    if (webmailProvider() === "proton" && IS_TOP_FRAME) {
      window.addEventListener("message", (event) => {
        if (!isTrustedProtonFrameMessage(event)) {
          return;
        }
        if (event.data?.type !== PROTON_FRAME_READY && event.data?.type !== PROTON_SCAN_RESULT) {
          return;
        }

        if (Array.isArray(event.data.flags) && event.data.flags.length > 0) {
          applyProtonIframeFlags(event.data.flags, event.data.identity ?? null);
          refreshLinkHoverListeners();
          return;
        }

        scheduleScan();
        refreshLinkHoverListeners();
      }, true);

      browserAPI.runtime.onMessage.addListener((message) => {
        if (message?.type !== "PROTON_IFRAME_SCAN") {
          return;
        }

        if (Array.isArray(message.flags) && message.flags.length > 0) {
          applyProtonIframeFlags(message.flags, message.identity ?? null);
          refreshLinkHoverListeners();
        }
      });
    }

    requestMacTrustedListSync().then(() => {
      scheduleScan();
    });

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") {
        requestMacTrustedListSync().then(() => {
          scheduleScan();
        });
      }
    });

    const observer = new MutationObserver(() => {
      if (!mailShieldEnabled) {
        return;
      }
      scheduleScan();
      watchProtonMessageFrames();
      refreshLinkHoverListeners();
    });

    observer.observe(document.documentElement, { childList: true, subtree: true });
    scheduleScan();
    watchProtonMessageFrames();
    refreshLinkHoverListeners();
    startProtonScanHeartbeat();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
  } else {
    bootstrap();
  }
})();
