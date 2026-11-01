<?php
// The current focus session, shared between the phone and the VS Code extension, plus what happened at the desk.
//   GET focus.php                         -> {"focus": {...} | null, "events": [...]}
//   POST {"focus": {...} | null}          (the app starts or ends a session)
//   POST {"event": {kind, answer, at}}     (VS Code: a desk break done or skipped, or active minutes)
// The app reads the events back and clears the ones it has stored (POST {"ack": <last at>}).
require __DIR__ . '/lib.php';
require_token();
$state = load('focus', ['focus' => null, 'events' => []]);
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	$body = json_decode(file_get_contents('php://input', false, null, 0, 100000), true);
	if (!is_array($body)) fail(400, 'bad request');
	if (array_key_exists('focus', $body)) $state['focus'] = is_array($body['focus']) ? $body['focus'] : null;
	if (is_array($body['event'] ?? null)) {
		$e = $body['event'];
		$state['events'][] = ['kind' => substr((string) ($e['kind'] ?? ''), 0, 30), 'answer' => substr((string) ($e['answer'] ?? ''), 0, 30), 'at' => (float) ($e['at'] ?? microtime(true) * 1000), 'minutes' => (int) ($e['minutes'] ?? 0)];
		$state['events'] = array_slice($state['events'], -500);
	}
	if (isset($body['ack'])) $state['events'] = array_values(array_filter($state['events'], fn($e) => $e['at'] > (float) $body['ack']));
	save('focus', $state);
}
reply($state);
