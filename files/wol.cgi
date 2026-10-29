#!/usr/bin/ucode
// Wake-on-LAN HTTP API, run by uhttpd as CGI.
//
//   GET  /cgi-bin/wol/lists
//   POST /cgi-bin/wol/lists/<list>/wake
//   POST /cgi-bin/wol/lists/<list>/hosts/<host>/wake
//
// Authentication: "Authorization: Bearer <token>".

'use strict';

import * as wm from 'wol_manager';

function reply(status, body, headers) {
	print(`Status: ${status}\r\n`);

	for (let k, v in headers ?? {})
		print(`${k}: ${v}\r\n`);

	print('Content-Type: application/json\r\n');
	print('Cache-Control: no-store\r\n\r\n');
	printf('%J\n', body);
	exit(0);
}

function require_method(method, allowed) {
	if (method != allowed)
		reply('405 Method Not Allowed', { error: 'method not allowed' }, { Allow: allowed });
}

function list_view(cfg, id) {
	const list = cfg.lists[id];

	return {
		id,
		name: list.name,
		hosts: map(list.hosts, (h) => ({ id: h, name: cfg.hosts[h].name, mac: cfg.hosts[h].mac }))
	};
}

const cfg = wm.load();

if (!cfg.enabled)
	reply('503 Service Unavailable', { error: 'service disabled' });

const auth = match(getenv('HTTP_AUTHORIZATION') ?? '', /^bearer +([^ ]+)$/i);
const user = wm.user_by_token(cfg, auth?.[1]);

if (!user)
	reply('401 Unauthorized', { error: 'invalid or missing token' },
		{ 'WWW-Authenticate': 'Bearer realm="wol-manager"' });

const method = getenv('REQUEST_METHOD');
const parts = filter(split(getenv('PATH_INFO') ?? '', '/'), (p) => p != '');
const n = length(parts);

if (n == 1 && parts[0] == 'lists') {
	require_method(method, 'GET');
	reply('200 OK', { user: user.id, lists: map(user.allow, (id) => list_view(cfg, id)) });
}

const is_wake_list = (n == 3 && parts[0] == 'lists' && parts[2] == 'wake');
const is_wake_host = (n == 5 && parts[0] == 'lists' && parts[2] == 'hosts' && parts[4] == 'wake');

if (!is_wake_list && !is_wake_host)
	reply('404 Not Found', { error: 'unknown endpoint' });

require_method(method, 'POST');

const list_id = parts[1];
const host_id = is_wake_host ? parts[3] : null;

if (!cfg.lists[list_id])
	reply('404 Not Found', { error: 'unknown list' });

if (!(list_id in user.allow))
	reply('403 Forbidden', { error: 'list not allowed' });

const hosts = wm.targets(cfg, list_id, host_id);

if (!hosts)
	reply('404 Not Found', { error: 'host not in this list' });

const results = map(hosts, (h) => wm.wake(h, `user=${user.id} list=${list_id}`));
const failed = length(filter(results, (r) => !r.ok));

reply(failed ? '500 Internal Server Error' : '200 OK', { list: list_id, results });
