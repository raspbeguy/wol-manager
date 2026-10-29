// Stand-in for the OpenWrt uci module, backed by the JSON file in $MOCK_UCI.

'use strict';

import { readfile, writefile } from 'fs';

const path = getenv('MOCK_UCI');

function find(db, config, section) {
	for (let s in db[config])
		if (s['.name'] == section)
			return s;

	return null;
}

function cursor() {
	const db = json(readfile(path));

	return {
		get_all: (config, section) => find(db, config, section),
		get: (config, section, option) => {
			const s = find(db, config, section);
			return s ? (option ? s[option] : s['.type']) : null;
		},
		foreach: (config, type, cb) => {
			for (let s in db[config])
				if (s['.type'] == type)
					cb(s);
			return true;
		},
		set: (config, section, option, value) => {
			find(db, config, section)[option] = value;
			return true;
		},
		delete: (config, section, option) => {
			delete find(db, config, section)[option];
			return true;
		},
		commit: (config) => writefile(path, sprintf('%J', db)) != null
	};
}

export { cursor };
