// Price history chart (#97): hand-written SVG, drawn at the box's real pixel size so text stays legible.
// Band = the low-high range, solid line = typical price, dashed line = lowest price where no typical
// is known, bars = units listed. Pointer and arrow keys pick a point; the tooltip shows its values.
import { currentSkin, h, s, skinMoney } from "./lib/dom";
import { moneyAxis, money, ticks } from "./lib/format";

export interface Point {
	x: number; // seconds
	lo: number | null;
	typ: number | null;
	hi: number | null;
	qty: number | null;
	title: string;
}

export interface Series {
	points: Point[];
	from: number;
	to: number;
	gapAfter: number; // seconds between neighbours that break the line
	xLabels: (x: number) => string;
	tipRows: [string, "lo" | "typ" | "hi"][]; // tooltip and spoken values, in order
	qtyLabel: string;
	summary: string;
}

export function chart(series: Series): HTMLElement {
	const box = h("div", { class: "chart", tabindex: "0", role: "group", "aria-label": `${series.summary} Use the arrow keys to read the values day by day.` });
	const live = h("p", { class: "sr", "aria-live": "polite" });
	const tip = h("div", { class: "tip chart-tip", "aria-hidden": "true" });
	const wrap = h("div", { class: "chart-wrap" }, box, tip, live);
	let sel = series.points.length - 1;
	let width = 0;

	const pts = series.points;
	const vals = pts.flatMap((p) => [p.lo, p.typ, p.hi]).filter((v): v is number => v !== null);
	const vLo = vals.length ? Math.min(...vals) : 0;
	const vHi = vals.length ? Math.max(...vals) : 1;
	const padV = (vHi - vLo) * 0.1 || Math.max(1, vHi * 0.1);
	const yMin = Math.max(0, vLo - padV);
	const yMax = vHi + padV;
	const qMax = Math.max(1, ...pts.map((p) => p.qty ?? 0));

	function draw(): void {
		width = Math.max(260, Math.round(box.clientWidth));
		const phone = width < 520;
		const H = phone ? 240 : 300;
		const L = phone ? 44 : 58; // y labels
		const R = 6;
		const plotTop = 10;
		const plotBottom = H - (phone ? 70 : 78);
		const barTop = plotBottom + 10;
		const barBottom = H - 22;
		const X = (x: number) => L + ((x - series.from) / Math.max(1, series.to - series.from)) * (width - L - R);
		const Y = (v: number) => plotBottom - ((v - yMin) / (yMax - yMin)) * (plotBottom - plotTop);
		const barW = Math.max(3, Math.min(16, ((width - L - R) / Math.max(pts.length, 8)) * 0.6));

		// Runs of neighbouring points (a gap longer than gapAfter breaks them).
		const runs: Point[][] = [];
		for (const p of pts) {
			const run = runs[runs.length - 1];
			const prev = run?.[run.length - 1];
			if (run && prev && p.x - prev.x <= series.gapAfter) run.push(p);
			else runs.push([p]);
		}
		const f = (n: number) => n.toFixed(1);
		const line = (list: Point[], key: "typ" | "lo") => {
			let d = "";
			let open = false;
			for (const p of list) {
				const v = p[key];
				if (v === null) {
					open = false;
					continue;
				}
				d += `${open ? "L" : "M"}${f(X(p.x))},${f(Y(v))}`;
				open = true;
			}
			return d;
		};
		const band = runs
			.map((run) => {
				const r = run.filter((p) => p.lo !== null && p.hi !== null);
				if (!r.length) return "";
				if (r.length === 1) {
					const p = r[0]!;
					const x = X(p.x);
					return `M${f(x - 4)},${f(Y(p.hi!))}H${f(x + 4)}V${f(Y(p.lo!))}H${f(x - 4)}Z`;
				}
				return `M${r.map((p) => `${f(X(p.x))},${f(Y(p.hi!))}`).join("L")}L${r
					.slice()
					.reverse()
					.map((p) => `${f(X(p.x))},${f(Y(p.lo!))}`)
					.join("L")}Z`;
			})
			.join("");
		const typD = runs.map((r) => line(r, "typ")).join("");
		// Lowest price only where a point has no typical price.
		const loD = runs.map((r) => line(r.map((p) => (p.typ === null ? p : { ...p, lo: null })), "lo")).join("");
		const yt = ticks(yMin, yMax, phone ? 4 : 5);

		const gaps: number[] = [];
		for (let i = 1; i < pts.length; i++) {
			if (pts[i]!.x - pts[i - 1]!.x > series.gapAfter) gaps.push((pts[i]!.x + pts[i - 1]!.x) / 2);
		}

		const p = pts[sel];
		const svg = s(
			"svg",
			{ width, height: H, viewBox: `0 0 ${width} ${H}`, "aria-hidden": "true" },
			yt.map((v) => s("line", { x1: L, x2: width - R, y1: f(Y(v)), y2: f(Y(v)), class: "grid" })),
			yt.map((v) => s("text", { x: L - 8, y: f(Y(v) + 4), "text-anchor": "end", class: "ylab" }, moneyAxis(v, currentSkin() === "velikopter"))),
			s("path", { d: band, class: "band" }),
			s("path", { d: loD, class: "loline" }),
			s("path", { d: typD, class: "typline" }),
			pts
				.filter((q) => q.typ !== null || q.lo !== null)
				.map((q) => {
					const v = q.typ ?? q.lo!;
					return s("circle", { cx: f(X(q.x)), cy: f(Y(v)), r: 2.6, class: q.typ !== null ? "dot" : "dot lo" });
				}),
			s("line", { x1: L, x2: width - R, y1: barBottom, y2: barBottom, class: "base" }),
			pts.map((q) => {
				if (!q.qty) return null;
				const bh = (q.qty / qMax) * (barBottom - barTop);
				return s("rect", { x: f(X(q.x) - barW / 2), y: f(barBottom - bh), width: f(barW), height: f(bh), class: "bar" });
			}),
			// "no scan" under a gap, unless it would run into the date labels at the ends.
			gaps
				.filter((x) => X(x) > L + 70 && X(x) < width - R - 70)
				.map((x) => s("text", { x: f(X(x)), y: H - 4, "text-anchor": "middle", class: "gap" }, "no scan")),
			s("text", { x: L, y: H - 4, class: "xlab" }, series.xLabels(series.from)),
			s("text", { x: width - R, y: H - 4, "text-anchor": "end", class: "xlab" }, series.xLabels(series.to)),
			p
				? [
						s("line", { x1: f(X(p.x)), x2: f(X(p.x)), y1: plotTop - 2, y2: barBottom, class: "cross" }),
						p.typ !== null || p.lo !== null ? s("circle", { cx: f(X(p.x)), cy: f(Y(p.typ ?? p.lo!)), r: 5.5, class: "hot" }) : null,
					]
				: null,
		);
		box.replaceChildren(svg);
		if (p) {
			fillTip(p);
			const tx = X(p.x);
			const tw = tip.offsetWidth || 212;
			tip.style.left = `${Math.max(0, Math.min(width - tw, tx + 18 > width - tw ? tx - tw - 18 : tx + 18))}px`;
			tip.hidden = false;
		} else {
			tip.hidden = true;
		}
	}

	function row(label: string, v: number | null): HTMLElement | null {
		if (v === null) return null;
		const m = skinMoney(v);
		return h("p", { class: "row" }, h("span", { class: "lbl" }, label), h("span", { class: "m" }, h("span", { class: "mp" }, m.parts.map((q) => h("span", { class: q.k }, q.v)))));
	}

	function fillTip(p: Point): void {
		tip.replaceChildren(
			h("p", { class: "tip-title" }, p.title),
			...series.tipRows.map(([label, key]) => row(label, p[key])).filter((e): e is HTMLElement => e !== null),
		);
		if (p.qty !== null) tip.append(h("p", { class: "row" }, h("span", { class: "lbl" }, series.qtyLabel), h("span", {}, `${p.qty.toLocaleString("en-US")} units`)));
	}

	function speak(): void {
		const p = pts[sel];
		if (!p) return;
		const part = (label: string, v: number | null) => (v === null ? null : `${label} ${money(v).label}`);
		live.textContent = [p.title, ...series.tipRows.map(([label, key]) => part(label, p[key])), p.qty !== null ? `${p.qty} units listed` : null]
			.filter(Boolean)
			.join(", ");
	}

	box.addEventListener("pointermove", (e) => {
		if (!pts.length) return;
		const rect = box.getBoundingClientRect();
		const L = width < 520 ? 44 : 58;
		const x = series.from + ((e.clientX - rect.left - L) / Math.max(1, width - L - 6)) * (series.to - series.from);
		let best = 0;
		pts.forEach((p, i) => {
			if (Math.abs(p.x - x) < Math.abs(pts[best]!.x - x)) best = i;
		});
		if (best !== sel) {
			sel = best;
			draw();
		}
	});
	box.addEventListener("keydown", (e) => {
		const k = (e as KeyboardEvent).key;
		const next = k === "ArrowLeft" ? sel - 1 : k === "ArrowRight" ? sel + 1 : k === "Home" ? 0 : k === "End" ? pts.length - 1 : null;
		if (next === null || !pts.length) return;
		e.preventDefault();
		sel = Math.max(0, Math.min(pts.length - 1, next));
		draw();
		speak();
	});
	new ResizeObserver(() => {
		if (Math.round(box.clientWidth) !== width) draw();
	}).observe(box);
	requestAnimationFrame(draw);
	return wrap;
}
