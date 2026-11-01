<?php
// Weight from Apple Health: a Shortcuts automation (daily, "Find Health Samples" of Weight) posts the readings and
// they reach the app as weight records, one per day. A weight you typed in the app is never replaced; a later
// Health reading for the same day replaces an earlier one.
//   POST {"kg": 78.4, "date": "2026-11-01T08:10:00+00:00", "unit": "kg"}        one reading
//   POST {"samples": [{"kg": ..., "date": ...}, ...]}                           several
//   POST text, one reading per line: "78,4 kg  1 Nov 2026 at 08:10"            what "Get Text" gives for a list
require __DIR__ . '/lib.php';
require_token();
$raw = file_get_contents('php://input', false, null, 0, 200000);
$body = json_decode($raw, true);
if (!is_array($body)) $body = $_POST ?: ['text' => $raw];

function number_of($v) {
	if (is_int($v) || is_float($v)) return (float) $v;
	if (!preg_match('/\d+(?:[.,]\d+)?/', (string) $v, $m)) return null;
	return (float) str_replace(',', '.', $m[0]);
}

function day_of($v) {
	if ($v === null || $v === '') return date('Y-m-d');
	$t = strtotime(str_replace(' at ', ' ', (string) $v));
	return $t ? date('Y-m-d', $t) : null;
}

$samples = [];
if (isset($body['samples']) && is_array($body['samples'])) $samples = $body['samples'];
elseif (isset($body['kg']) || isset($body['value'])) $samples = [$body];
else {
	foreach (preg_split('/\R/', (string) ($body['text'] ?? '')) as $line) {
		if (!preg_match('/^\s*(\d+(?:[.,]\d+)?)\s*(kg|lb|lbs)?\s*(.*)$/i', $line, $m)) continue;
		$samples[] = ['kg' => $m[1], 'unit' => $m[2] ?: 'kg', 'date' => trim($m[3])];
	}
}

$days = [];
foreach ($samples as $s) {
	if (!is_array($s)) continue;
	$value = number_of($s['kg'] ?? $s['value'] ?? null);
	$unit = strtolower((string) ($s['unit'] ?? (preg_match('/lb/i', (string) ($s['kg'] ?? $s['value'] ?? '')) ? 'lb' : 'kg')));
	if ($value !== null && strpos($unit, 'lb') === 0) $value *= 0.45359237;
	$date = day_of($s['date'] ?? null);
	if ($value === null || $value < 30 || $value > 300 || !$date || $date > date('Y-m-d', strtotime('+1 day'))) continue;
	$days[$date] = round($value, 2); // the last reading of a day wins
}
if (!$days) fail(400, 'no weight readings');

$records = [];
foreach ($days as $date => $kg) $records[] = ['weight', $date, ['date' => $date, 'kg' => $kg, 'source' => 'health']];
// replace only earlier Health readings that differ
$added = store_put($records, function ($old) use ($days) {
	$d = $old['data'] ?? [];
	return ($d['source'] ?? '') === 'health' && abs(($d['kg'] ?? 0) - ($days[$d['date'] ?? ''] ?? 0)) > 0.001;
});
reply(['ok' => true, 'days' => count($days), 'saved' => $added]);
