// Building blocks the private pages share (/me, /me/fishing): panes, bar heads, key/value lines, bars, the
// character tabs. One place for the markup, so a reskin changes the CSS only.
import { h } from "./dom";
import { type Character, classKey, fullName, share } from "./me";

export function n(v: number | null): string {
	return v === null ? "–" : v.toLocaleString("en-US");
}

export function kv(label: string, value: Node | string, hint?: string | null): HTMLElement[] {
	const out = [h("p", { class: "kv" }, h("span", {}, label), typeof value === "string" ? h("span", {}, value) : value)];
	if (hint) out.push(h("p", { class: "hint kv-hint" }, hint));
	return out;
}

export function barHead(text: string): HTMLElement {
	return h("h2", { class: "bar-head" }, text);
}

export function pane(cls: string, sec: string, ...children: (Node | null)[]): HTMLElement {
	return h("section", { class: `pane me-pane ${cls}`, "data-sec": sec }, ...children);
}

export function well(...children: Node[]): HTMLElement {
	return h("div", { class: "inset tscroll" }, ...children);
}

export function bar(cls: string, part: number, whole: number, text: string, label: string): HTMLElement {
	const el = h("div", { class: `sbar ${cls}`, role: "img", "aria-label": label }, h("i", {}), h("b", {}, text));
	(el.firstChild as HTMLElement).style.width = `${(share(part, whole) * 100).toFixed(1)}%`;
	return el;
}

// The characters as tabs (Classic: the profession window's side column; Velikopter: a row of square keys).
export function sideTabs(chars: Character[], current: string | null, href: (key: string) => string, pick: (e: Event, key: string) => void): HTMLElement {
	return h(
		"nav",
		{ class: "sidetabs", "aria-label": "Characters" },
		chars.map((ch) =>
			h(
				"a",
				{
					href: href(ch.key),
					class: `stab cls-${classKey(ch.class)}`,
					"aria-current": ch.key === current ? "page" : null,
					"aria-label": `${fullName(ch)}, ${[ch.level !== null ? `level ${ch.level}` : null, ch.class].filter(Boolean).join(" ")}`,
					title: fullName(ch),
					onclick: (e: Event) => pick(e, ch.key),
				},
				(ch.name ?? ch.key).charAt(0),
				ch.level !== null ? h("span", { class: "lv", "aria-hidden": "true" }, String(ch.level)) : null,
			),
		),
	);
}
