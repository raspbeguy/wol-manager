// Shared logic for wol-manager: configuration, token authentication and
// Wake-on-LAN. Used by the CGI endpoint, the CLI tool and the rpcd plugin.

'use strict';

import { cursor } from 'uci';
import { readfile } from 'fs';
import { sha256 } from 'digest';

const CONFIG = 'wol_manager';
const ETHERWAKE = '/usr/bin/etherwake';
const TOKEN_BYTES = 32;

const RE_ID = /^[A-Za-z0-9_]+$/;
const RE_MAC = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/;
const RE_IFACE = /^[A-Za-z0-9_.-]{1,15}$/;
const RE_TOKEN = /^[0-9a-f]{64}$/;

function to_list(v) {
	if (type(v) == 'array')
		return v;

	return (v != null) ? [ v ] : [];
}

function is_id(s) {
	return type(s) == 'string' && match(s, RE_ID) != null;
}

// Read the configuration. Invalid hosts and dangling references are left
// out of the result and reported in `errors`.
function load() {
	const uci = cursor();
	const globals = uci.get_all(CONFIG, 'globals') ?? {};
	const cfg = {
		enabled: globals.enabled != '0',
		iface: globals.iface ?? 'br-lan',
		hosts: {},
		lists: {},
		users: {},
		errors: []
	};

	uci.foreach(CONFIG, 'host', (s) => {
		const id = s['.name'];
		const iface = s.iface ?? cfg.iface;

		if (type(s.mac) != 'string' || !match(s.mac, RE_MAC))
			push(cfg.errors, `host '${id}': invalid MAC address '${s.mac ?? ''}'`);
		else if (!match(iface, RE_IFACE))
			push(cfg.errors, `host '${id}': invalid interface '${iface}'`);
		else
			cfg.hosts[id] = { id, name: s.name ?? id, mac: uc(s.mac), iface };
	});

	uci.foreach(CONFIG, 'hostlist', (s) => {
		const id = s['.name'];
		const hosts = [];

		for (let h in to_list(s.host)) {
			if (cfg.hosts[h])
				push(hosts, h);
			else
				push(cfg.errors, `hostlist '${id}': unknown or invalid host '${h}'`);
		}

		cfg.lists[id] = { id, name: s.name ?? id, hosts };
	});

	uci.foreach(CONFIG, 'user', (s) => {
		const id = s['.name'];
		const allow = [];

		for (let l in to_list(s.allow)) {
			if (cfg.lists[l])
				push(allow, l);
			else
				push(cfg.errors, `user '${id}': unknown hostlist '${l}'`);
		}

		cfg.users[id] = {
			id,
			enabled: s.enabled != '0',
			has_token: s.token_hash != null,
			token_hash: s.token_hash,
			allow
		};
	});

	return cfg;
}

function check() {
	return load().errors;
}

// Return the enabled user that owns this token, or null.
function user_by_token(cfg, token) {
	if (type(token) != 'string' || !match(token, RE_TOKEN))
		return null;

	const hash = sha256(token);

	for (let id, u in cfg.users)
		if (u.enabled && u.token_hash == hash)
			return u;

	return null;
}

// Return the hosts to wake: all hosts of the list, or only `host_id` if it
// is in the list. Return null if the list or the host is not found.
function targets(cfg, list_id, host_id) {
	const list = cfg.lists[list_id];

	if (!list)
		return null;

	if (host_id == null)
		return map(list.hosts, (h) => cfg.hosts[h]);

	return (host_id in list.hosts) ? [ cfg.hosts[host_id] ] : null;
}

// Send the magic packet. `who` describes the caller for the syslog line.
function wake(host, who) {
	const rc = system([ ETHERWAKE, '-i', host.iface, host.mac ]);
	const ok = (rc == 0);

	system([ 'logger', '-t', 'wol-manager',
		`${who} host=${host.id} mac=${host.mac} iface=${host.iface} result=${ok ? 'ok' : 'error ' + rc}` ]);

	return { host: host.id, mac: host.mac, ok };
}

// Create a new token for an existing user. Only the SHA-256 hash is stored.
// Return the token in clear text, or null if the user does not exist.
function token_new(user_id) {
	const uci = cursor();

	if (!is_id(user_id) || uci.get(CONFIG, user_id) != 'user')
		return null;

	const raw = readfile('/dev/urandom', TOKEN_BYTES);

	if (raw == null || length(raw) != TOKEN_BYTES)
		return null;

	const token = hexenc(raw);

	uci.set(CONFIG, user_id, 'token_hash', sha256(token));
	uci.commit(CONFIG);

	return token;
}

// Remove the token of a user. Return false if the user does not exist.
function token_revoke(user_id) {
	const uci = cursor();

	if (!is_id(user_id) || uci.get(CONFIG, user_id) != 'user')
		return false;

	uci.delete(CONFIG, user_id, 'token_hash');
	uci.commit(CONFIG);

	return true;
}

export { is_id, load, check, user_by_token, targets, wake, token_new, token_revoke };
