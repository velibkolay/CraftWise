// Small DOM helpers and the page chrome both pages share. Text always goes in as text nodes.
import type { House } from "./api";
import { age, freshness, money } from "./format";

type Child = Node | string | number | null | undefined | false | Child[];
type Attrs = Record<string, string | number | boolean | null | undefined | ((e: Event) => void)>;

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Attrs = {}, ...children: Child[]): HTMLElementTagNameMap[K] {
	const el = document.createElement(tag);
	setAttrs(el, attrs);
	append(el, children);
	return el;
}

const SVG = "http://www.w3.org/2000/svg";
export function s(tag: string, attrs: Attrs = {}, ...children: Child[]): SVGElement {
	const el = document.createElementNS(SVG, tag);
	setAttrs(el, attrs);
	append(el, children);
	return el;
}

function setAttrs(el: Element, attrs: Attrs): void {
	for (const [k, v] of Object.entries(attrs)) {
		if (v === null || v === undefined || v === false) continue;
		if (typeof v === "function") el.addEventListener(k.slice(2), v);
		else el.setAttribute(k, v === true ? "" : String(v));
	}
}

export function append(el: Node, children: Child[]): void {
	for (const c of children) {
		if (c === null || c === undefined || c === false) continue;
		if (Array.isArray(c)) append(el, c);
		else el.appendChild(typeof c === "string" || typeof c === "number" ? document.createTextNode(String(c)) : c);
	}
}

export function clear(el: Element, ...children: Child[]): void {
	el.replaceChildren();
	append(el, children);
}

// Money with spoken text: screen readers read "1 gold 12 silver", the eye sees coins.
export function moneyEl(copper: number | null, empty = "–"): HTMLElement {
	if (copper === null) return h("span", { class: "m none" }, h("span", { "aria-hidden": "true" }, empty), h("span", { class: "sr" }, "no price"));
	const m = money(copper);
	return h(
		"span",
		{ class: "m" },
		h("span", { class: "sr" }, m.label),
		h("span", { class: "mp", "aria-hidden": "true" }, m.parts.map((p) => h("span", { class: p.k }, p.v))),
	);
}

export function nowSeconds(): number {
	return Math.floor(Date.now() / 1000);
}

// ---- Skin --------------------------------------------------------------------------------------

const SKIN_KEY = "cw-skin";
export type Skin = "classic" | "velikopter";

export function currentSkin(): Skin {
	return document.documentElement.dataset.skin === "velikopter" ? "velikopter" : "classic";
}

export function setSkin(skin: Skin): void {
	document.documentElement.dataset.skin = skin;
	try {
		localStorage.setItem(SKIN_KEY, skin);
	} catch {
		// private mode: the choice lasts for this page only
	}
	for (const b of document.querySelectorAll<HTMLButtonElement>(".skinswitch button")) {
		b.setAttribute("aria-pressed", String(b.dataset.skin === skin));
	}
}

export function skinSwitch(): HTMLElement {
	const btn = (skin: Skin, label: string) =>
		h("button", { type: "button", class: "wtab up", "data-skin": skin, "aria-pressed": String(currentSkin() === skin), onclick: () => setSkin(skin) }, label);
	return h("div", { class: "skinswitch", role: "group", "aria-label": "Look of the site" }, btn("classic", "Classic"), btn("velikopter", "Velikopter"));
}

// ---- Shared chrome --------------------------------------------------------------------------------

export function rotor(size = 26): SVGElement {
	return s(
		"svg",
		{ width: size, height: size, viewBox: "0 0 100 100", "aria-hidden": "true", class: "rotor" },
		s(
			"g",
			{ transform: "rotate(-12 50 50)" },
			[0, 120, 240].map((r) => s("rect", { x: 44, y: 8, width: 13, height: 42, rx: 5, transform: `rotate(${r} 50 50)` })),
		),
		s("circle", { cx: 50, cy: 50, r: 11, class: "hub" }),
	);
}

export function topBar(sub: Node | string): HTMLElement {
	return h(
		"header",
		{ class: "top" },
		h("a", { href: "/", class: "brand" }, rotor(), h("span", {}, "Velikopter Market")),
		h("span", { class: "hint crumbs" }, sub),
		h("span", { class: "grow" }),
		skinSwitch(),
	);
}

// The scan status bar of the main house: full right after a scan, empty (stale) after 24 h.
export function statusBar(house: House | null): HTMLElement {
	if (!house || house.lastScan === null) {
		return h("div", { class: "sbar", role: "status" }, h("i", { style: "width:0" }), h("b", {}, "No scans yet"));
	}
	const since = nowSeconds() - house.lastScan;
	const stale = since > 86400;
	const text = `${house.label}, scanned ${age(since)}${stale ? ", prices are stale" : ""}`;
	const bar = h("div", { class: `sbar${stale ? " stale" : ""}`, role: "img", "aria-label": `Last scan: ${text}` }, h("i", {}), h("b", {}, text));
	(bar.firstChild as HTMLElement).style.width = `${Math.round(freshness(since) * 100)}%`;
	return bar;
}

export type View = "browse" | "favourites" | "crates" | "me";

export function bottomTabs(active: View | null): HTMLElement {
	const tab = (view: View, href: string, label: string) =>
		h("a", { class: "wtab down", href, "data-view": view, "aria-current": active === view ? "page" : null }, label);
	return h(
		"nav",
		{ class: "btabs", "aria-label": "Views" },
		tab("browse", "/", "Browse"),
		tab("favourites", "/?view=favourites", "Favourites"),
		tab("crates", "/?view=crates", "Waylaid Crates"),
		tab("me", "/me", "My Characters"),
	);
}

export function closeButton(href: string, label: string): HTMLElement {
	return h(
		"a",
		{ class: "xbtn", href, "aria-label": label },
		s(
			"svg",
			{ width: 12, height: 12, viewBox: "0 0 12 12", "aria-hidden": "true" },
			s("path", { d: "M2 2 L10 10 M10 2 L2 10", class: "x-under" }),
			s("path", { d: "M2 2 L10 10 M10 2 L2 10", class: "x-over" }),
		),
	);
}

// Placeholder icon slot (no client icon art is served): the item's initial on a quality-tinted slot.
export function slot(name: string | null, quality: string, size: "" | "lg" | "ring" = ""): HTMLElement {
	return h("span", { class: `${size === "ring" ? "ring" : "slot"} ${size === "lg" ? "lg" : ""} ${quality}`, "aria-hidden": "true" }, (name ?? "?").charAt(0));
}

export function errorBox(text: string): HTMLElement {
	return h("p", { class: "notice", role: "alert" }, text);
}
