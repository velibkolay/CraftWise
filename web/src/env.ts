export interface Env {
	DB: D1Database;
	ASSETS: Fetcher;
	ACCESS_TEAM_DOMAIN: string;
	ACCESS_AUD?: string;
	// Daily rows written CraftWise may use (#145); parsed by parseWriteBudget (src/limits.ts).
	WRITE_BUDGET?: string;
}
