// Node globals the SDK's dependencies expect, for the browser bundle.
import { Buffer } from 'buffer';
import process from '../node_modules/process/browser.js';
// The shim's nextTick is a setTimeout(0), which WebKit clamps to 4 ms once
// timers nest; every database read through a level stream waits on several.
// Node runs nextTick before the next task, so a microtask is the faithful copy.
process.nextTick = (fn, ...args) => queueMicrotask(() => fn(...args));
export { Buffer, process };
