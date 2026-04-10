import { WebPlugin } from '@capacitor/core';
import type { triptrackingPlugin } from './definitions';

export class triptrackingWeb extends WebPlugin implements triptrackingPlugin {
  async doSomething(options: { input: string }): Promise<{ value: string }> {
    return { value: 'Web fallback: ' + options.input };
  }
}
