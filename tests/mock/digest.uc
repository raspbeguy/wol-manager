// Stand-in for the OpenWrt digest module. The library only hashes tokens it
// has already checked to be hex, so passing the input through a shell is safe.

'use strict';

import { popen } from 'fs';

function sha256(s) {
	const p = popen(`printf %s '${s}' | sha256sum`);
	const out = p.read('all');
	p.close();

	return substr(out, 0, 64);
}

export { sha256 };
