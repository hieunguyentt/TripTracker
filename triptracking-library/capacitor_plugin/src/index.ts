import { registerPlugin } from '@capacitor/core';
import type { triptrackingPlugin } from './definitions';

const triptracking = registerPlugin<triptrackingPlugin>('triptracking', {
  web: () => import('./web').then(m => new m.triptrackingWeb()),
});

export * from './definitions';
export { triptracking };
