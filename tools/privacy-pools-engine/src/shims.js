// Stand-ins for the Node-only modules the SDK's bundle names but the phone
// never runs (build.mjs aliases each module name to one export set here).
//
// - `fs/promises` and `path`: only the SDK's FileStorageService and
//   LocalCircuitArtifacts touch them. The engine keeps notes in memory and
//   asks the app for circuits, so any call here is a wiring bug: it throws.
// - `crypto`: the SDK imports `randomUUID` for a corrupt-file rename only.
// - `pino`: a silent logger; the engine passes its own logger everywhere.
// - `@lifi/sdk`: swaps and cross-chain deposits go through LiFi, which the
//   app does not use (prd §1539: swaps go straight to the exchanges). Every
//   call throws, so nothing can reach li.quest even by accident.

const refuse = (what) => () => { throw new Error(`${what} is not available in the phone engine`); };

// fs/promises
export const readFile = refuse('fs.readFile');
export const writeFile = refuse('fs.writeFile');
export const rename = refuse('fs.rename');
export const mkdir = refuse('fs.mkdir');

// path
export const join = (...parts) => parts.join('/').replace(/\/+/g, '/');
export const dirname = (p) => p.replace(/\/[^/]*$/, '') || '/';

// crypto
export const randomUUID = () => globalThis.crypto.randomUUID();

// @lifi/sdk
export const createClient = () => ({});
export const getQuote = refuse('LiFi');
export const getContractCallsQuote = refuse('LiFi');
