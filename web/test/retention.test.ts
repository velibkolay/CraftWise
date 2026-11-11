import { createExecutionContext, createScheduledController, env, waitOnExecutionContext } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import worker, { retention } from "../src/index";
import { clearData, HORDE, houses, makeToken, now, upload } from "./helpers";

const DAY = 86400;

beforeEach(clearData);

describe("daily retention (cron)", () => {
	it("drops raw points after 30 days and keeps daily rows, prices and items", async () => {
		const token = await makeToken("public");
		const t = now();
		const tiers = [10, 1];
		const res = await upload(token, {
			v: 1,
			houses: houses(),
			items: { "2589": { n: "Linen Cloth" } },
			scans: [
				{ house: HORDE, t: t - 100 * DAY, kind: "full" },
				{ house: HORDE, t, kind: "full" },
			],
			prices: [
				{
					item: "2589",
					house: HORDE,
					last: { t, min: 10, qty: 1 },
					raw: [
						{ t: t - 31 * DAY, total: 1, tiers },
						{ t: t - 29 * DAY, total: 1, tiers },
						{ t, total: 1, tiers },
					],
					days: [{ day: Math.floor((t - 400 * DAY) / DAY), lo: 10, typ: 10, hi: 10, n: 1 }],
				},
			],
		});
		expect(res.status).toBe(200);
		const written = await retention(env, t);
		expect(written).toBe(2); // one point, one scan
		const points = await env.DB.prepare("SELECT t FROM points ORDER BY t").all();
		expect(points.results.map((r) => r.t)).toEqual([t - 29 * DAY, t]);
		expect((await env.DB.prepare("SELECT count(*) AS n FROM scans").first<{ n: number }>())!.n).toBe(1);
		expect((await env.DB.prepare("SELECT count(*) AS n FROM daily").first<{ n: number }>())!.n).toBe(2);
		expect((await env.DB.prepare("SELECT count(*) AS n FROM items").first<{ n: number }>())!.n).toBe(1);
	});

	it("runs from the scheduled handler", async () => {
		const ctx = createExecutionContext();
		await worker.scheduled(createScheduledController({ scheduledTime: Date.now(), cron: "17 3 * * *" }), env, ctx);
		await waitOnExecutionContext(ctx);
		const usage = await env.DB.prepare("SELECT uploads FROM usage").first<{ uploads: number }>();
		expect(usage).toEqual({ uploads: 0 });
	});
});
