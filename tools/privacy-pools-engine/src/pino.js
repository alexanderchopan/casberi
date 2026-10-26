// A silent pino: the SDK's PinoLogger default. The engine hands the SDK its
// own logger (engine.js), so this only answers calls nothing reads.
function make() {
  const self = { level: 'silent' };
  for (const name of ['trace', 'debug', 'info', 'warn', 'error', 'fatal']) self[name] = () => {};
  self.child = () => make();
  return self;
}
export default function pino() { return make(); }
