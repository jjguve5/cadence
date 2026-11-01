<?php
// Cadence sync: every synced thing is a record ("<type>:<id>") with a JSON body, stamped with the server's
// revision counter when it last changed. A device sends what changed on it and gets back everything newer than the
// revision it last saw. Deletes stay as records (deleted: true) so they reach the other devices.
//   POST {"since", "changes": [{"type", "id", "deleted"?, "data"?, "updated"?}]}  ->  {"rev", "changes": [records]}
// When two devices change the same record, the later "updated" (ms since 1970, set by the device) wins.
// Record bodies are kept as JSON text, so empty objects stay {} (PHP arrays would turn them into []).
require __DIR__ . '/lib.php';
require_token();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') fail(405, 'POST only');

$raw = file_get_contents('php://input', false, null, 0, 8000000);
$request = json_decode($raw, true);
$objects = json_decode($raw); // the same request with objects kept as objects
if (!is_array($request)) fail(400, 'bad request');
$since = (int) ($request['since'] ?? 0);
$changes = $request['changes'] ?? [];
if (!is_array($changes) || count($changes) > 5000) fail(400, 'bad changes');

$file = data_path('store');
$handle = fopen($file, 'c+');
if (!$handle) fail(500, 'cannot open the store');
flock($handle, LOCK_EX);
$store = json_decode(substr(stream_get_contents($handle), strlen(GUARD)), true);
if (!is_array($store)) $store = ['rev' => 0, 'records' => []];

$changed = false;
foreach ($changes as $n => $change) {
	$type = $change['type'] ?? '';
	$id = $change['id'] ?? '';
	if (!is_string($type) || !preg_match('/^[a-z][a-zA-Z0-9]{0,31}$/', $type)) continue;
	if (!is_string($id) || !preg_match('/^[A-Za-z0-9_.:-]{1,80}$/', $id)) continue;
	$data = $objects->changes[$n]->data ?? null;
	$json = $data === null ? null : json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	if ($json !== null && (!is_object($data) || strlen($json) > 200000)) continue;
	$updated = (int) ($change['updated'] ?? 0);
	$key = "$type:$id";
	$old = $store['records'][$key] ?? null;
	if ($old && $updated && ($old['updated'] ?? 0) > $updated) continue; // a newer edit is already here
	$deleted = !empty($change['deleted']);
	$store['rev']++;
	$store['records'][$key] = [
		'type' => $type,
		'id' => $id,
		'rev' => $store['rev'],
		'updated' => $updated,
		'deleted' => $deleted,
		'json' => $deleted ? null : $json,
	];
	$changed = true;
}

if ($changed) {
	ftruncate($handle, 0);
	rewind($handle);
	fwrite($handle, GUARD . json_encode($store, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
	fflush($handle);
}
flock($handle, LOCK_UN);
fclose($handle);

// A device ahead of the server (the store was reset) gets everything
if ($since > $store['rev']) $since = 0;
$newer = [];
foreach ($store['records'] as $record) {
	if ($record['rev'] <= $since) continue;
	// Older records (and server-made ones) still hold "data"; new ones hold the JSON text
	if (array_key_exists('json', $record)) $record['data'] = $record['json'] === null ? null : json_decode($record['json']);
	else $record['data'] = $record['data'] === null ? null : json_decode(json_encode($record['data']));
	unset($record['json']);
	$newer[] = $record;
}
reply(['rev' => $store['rev'], 'changes' => $newer]);
