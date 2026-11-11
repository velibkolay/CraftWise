// Vite ?raw imports: a file as text (the page tests read public/*.html and public/_headers).
declare module "*?raw" {
	const text: string;
	export default text;
}
