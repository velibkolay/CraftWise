// Headers of the pages the Worker serves itself (/item/<id>); the same as public/_headers gives the
// static pages (test/site.test.ts keeps the two equal).
export const PAGE_HEADERS: Record<string, string> = {
	"content-security-policy":
		"default-src 'self'; script-src 'self' 'sha256-HXF2BSiwha4cb040xX9t24f5ZrwfdKiIDOajUqGVbck='; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
	"x-content-type-options": "nosniff",
	"referrer-policy": "same-origin",
};
