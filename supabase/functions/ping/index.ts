import { handlePing, serveAction } from "../_shared/server.ts";

serveAction((_req) => handlePing());
