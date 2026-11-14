// The addon's watch list (#165): uploaded with the private upload, read at /api/me/watch.
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { access, accessJwt, accessKey, bearer, call, clearData, makeToken, now, serveAccessKeys, type AccessKey } from "./helpers";

let key: AccessKey;
beforeAll(async () => {
	key = await accessKey("k1");
});
beforeEach(async () => {
	await clearData();
	serveAccessKeys([key]);
});
afterEach(() => {
	vi.restoreAllMocks();
});

const up = (token: string, body: unknown) => call("POST", "/api/private/upload", { body, headers: bearer(token) });
async function stored(): Promise<{ item: number; added: number }[]> {
	const res = await call("GET", "/api/me/watch", { headers: access(await accessJwt(key)) });
	expect(res.status).toBe(200);
	expect(res.headers.get("cache-control")).toBe("private, no-store");
	return (await res.json<{ watch: { item: number; added: number }[] }>()).watch;
}

describe("watch list", () => {
	it("needs an Access login to read", async () => {
		expect((await call("GET", "/api/me/watch")).status).toBe(403);
	});

	it("stores the list, newest first, and replaces it as a whole", async () => {
		const token = await makeToken("private");
		const t = now();
		let res = await up(token, { v: 1, watch: [{ i: 2589, t: t - 100 }, { i: 4306, t: t - 50 }, { i: 2589, t: t - 1 }] });
		expect(res.status).toBe(200);
		const body = await res.json<{ received: { watch: number } }>();
		expect(body.received.watch).toBe(2); // the duplicate is dropped
		expect(await stored()).toEqual([
			{ item: 4306, added: t - 50 },
			{ item: 2589, added: t - 100 },
		]);
		// 4306 unwatched, 5000 watched, 2589 unchanged
		res = await up(token, { v: 1, watch: [{ i: 2589, t: t - 100 }, { i: 5000, t: t - 5 }] });
		expect(res.status).toBe(200);
		expect(await stored()).toEqual([
			{ item: 5000, added: t - 5 },
			{ item: 2589, added: t - 100 },
		]);
	});

	it("writes nothing when the list is sent again", async () => {
		const token = await makeToken("private");
		const body = { v: 1, watch: [{ i: 2589, t: now() - 100 }, { i: 4306, t: now() - 50 }] };
		await up(token, body);
		const again = await up(token, body);
		expect((await again.json<{ rowsWritten: number }>()).rowsWritten).toBe(1); // the rate-limit row
	});

	it("an empty list clears it; an upload without the field leaves it alone", async () => {
		const token = await makeToken("private");
		const t = now();
		await up(token, { v: 1, watch: [{ i: 2589, t }] });
		const other = { v: 1, ledger: [{ t, c: "Realm-Name Sur", k: "vsell", i: 1, q: 1, m: 1 }] };
		expect((await up(token, other)).status).toBe(200);
		expect(await stored()).toHaveLength(1);
		expect((await up(token, { v: 1, watch: [] })).status).toBe(200);
		expect(await stored()).toEqual([]);
	});

	it("refuses a malformed list", async () => {
		const token = await makeToken("private");
		const t = now();
		for (const watch of [{}, [1], [{ i: 0, t }], [{ i: 5, t: 5 }], [{ i: "5", t }], [{ i: 5 }], Array.from({ length: 1001 }, (_, i) => ({ i: i + 1, t }))]) {
			const res = await up(token, { v: 1, watch });
			expect(res.status, JSON.stringify(watch).slice(0, 60)).toBe(400);
			expect((await res.json<{ error: string }>()).error).toBe("bad_shape");
		}
	});
});
