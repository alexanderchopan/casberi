// aztec.js reads a global Buffer in places; the browser has none.
import { Buffer } from 'buffer';
export { Buffer };
