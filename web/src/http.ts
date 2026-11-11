export class HttpError extends Error {
	constructor(
		readonly status: number,
		readonly code: string,
		message: string,
		readonly headers: Record<string, string> = {},
	) {
		super(message);
	}
}

export function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: { "content-type": "application/json; charset=utf-8", ...headers },
	});
}

export function errorResponse(e: HttpError): Response {
	return json({ error: e.code, message: e.message }, e.status, { "cache-control": "no-store", ...e.headers });
}

// Reads a request body as text, refusing more than `max` bytes (also when Content-Length lies).
export async function readBody(request: Request, max: number): Promise<string> {
	const declared = Number(request.headers.get("content-length") ?? "0");
	if (declared > max) {
		throw new HttpError(413, "too_large", `body over ${max} bytes`);
	}
	const reader = request.body?.getReader();
	if (!reader) {
		throw new HttpError(400, "empty_body", "request body missing");
	}
	const chunks: Uint8Array[] = [];
	let size = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		size += value.byteLength;
		if (size > max) {
			await reader.cancel();
			throw new HttpError(413, "too_large", `body over ${max} bytes`);
		}
		chunks.push(value);
	}
	const all = new Uint8Array(size);
	let at = 0;
	for (const c of chunks) {
		all.set(c, at);
		at += c.byteLength;
	}
	return new TextDecoder().decode(all);
}

export function parseJson(text: string): unknown {
	try {
		return JSON.parse(text);
	} catch {
		throw new HttpError(400, "bad_json", "body is not valid JSON");
	}
}

// Integer query parameter clamped to [min, max]; `fallback` when missing or not a number.
export function intParam(url: URL, name: string, fallback: number, min: number, max: number): number {
	const raw = url.searchParams.get(name);
	const n = raw === null ? NaN : Number(raw);
	if (!Number.isInteger(n)) return fallback;
	return Math.min(max, Math.max(min, n));
}
