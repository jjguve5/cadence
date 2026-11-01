<?php
// The Fitbit data the app needs, one record per day, from the Google Health API.
//   GET health.php?days=14          -> {"device", "days": [{date, sleep, steps, rhr, hrv, spo2, breathing, temp, vo2, azm, calories}]}
//   GET health.php?raw=<data-type>  -> the API's own answer for the last 3 days of that type, to check field names
// Days older than 3 days come from a cache (data/health.php); recent ones are fetched again, since the Air syncs late.
require __DIR__ . '/lib.php';
require __DIR__ . '/google_token.php';
require_token();
set_time_limit(120);
const API = 'https://health.googleapis.com/v4/users/me/';

function api($method, $path, $body = null) {
	$headers = ['Authorization: Bearer ' . access_token()];
	if ($body !== null) $headers[] = 'Content-Type: application/json';
	[$status, $json] = http($method, API . $path, $headers, $body === null ? null : json_encode($body));
	if ($status === 401) fail(409, 'google sign-in expired', ['reconnect' => true]);
	return [$status, $json];
}

// Every page of a list or reconcile call
function all_points($path) {
	$points = [];
	$token = '';
	for ($page = 0; $page < 20; $page++) {
		[$status, $json] = api('GET', $path . ($token ? '&pageToken=' . rawurlencode($token) : ''));
		if ($status !== 200) return [$points, $json['error']['message'] ?? "HTTP $status"];
		$points = array_merge($points, $json['dataPoints'] ?? []);
		$token = $json['nextPageToken'] ?? '';
		if (!$token) break;
	}
	return [$points, null];
}

function local_date($time, $offset) {
	return gmdate('Y-m-d', strtotime($time) + (int) $offset);
}

function civil($date) {
	[$y, $m, $d] = array_map('intval', explode('-', $date));
	return ['date' => ['year' => $y, 'month' => $m, 'day' => $d]];
}

function civil_date($value) {
	if (!is_array($value)) return null;
	$d = $value['date'] ?? $value;
	if (!isset($d['year'], $d['month'], $d['day'])) return null;
	return sprintf('%04d-%02d-%02d', $d['year'], $d['month'], $d['day']);
}

// The numbers inside a data point, flattened to "path" => value, so field names can change without breaking us
function numbers($value, $prefix = '') {
	$out = [];
	foreach ((array) $value as $key => $item) {
		$path = $prefix === '' ? (string) $key : "$prefix.$key";
		if (is_array($item)) $out += numbers($item, $path);
		elseif (is_numeric($item) && !preg_match('/(^|\.)(date|year|month|day|hours|minutes|seconds|nanos)(\.|$)/i', $path)) $out[$path] = (float) $item;
	}
	return $out;
}

function pick($numbers, $patterns) {
	foreach ($patterns as $pattern) {
		foreach ($numbers as $path => $value) if (preg_match($pattern, $path)) return $value;
	}
	return null;
}

function find_date($point) {
	foreach ($point as $key => $value) {
		if (!is_array($value)) continue;
		if ($key === 'date' && ($d = civil_date($value))) return $d;
		foreach (['date', 'civilStartTime', 'sampleTime'] as $field) {
			if (isset($value[$field]) && ($d = civil_date($value[$field]))) return $d;
		}
		if ($d = find_date($value)) return $d;
	}
	return null;
}

$days = max(1, min(90, (int) ($_GET['days'] ?? 14)));
$today = date('Y-m-d');

if (isset($_GET['raw'])) {
	$type = preg_replace('/[^a-z0-9-]/', '', $_GET['raw']);
	$camel = lcfirst(str_replace(' ', '', ucwords(str_replace('-', ' ', $type))));
	$from = date('Y-m-d', strtotime('-3 days'));
	$filter = $_GET['filter'] ?? (str_starts_with($type, 'daily-') ? "$camel.date >= \"$from\"" : "$camel.interval.start_time >= \"" . gmdate('Y-m-d\TH:i:s\Z', strtotime('-1 day')) . '"');
	reply(api('GET', "dataTypes/$type/dataPoints?pageSize=3" . ($filter === 'none' ? '' : '&filter=' . rawurlencode($filter)))[1]);
}

// Workouts the Air recorded (runs, walks, sessions with heart rate), for the last N days
//   GET health.php?exercise=14  ->  {"exercises": [{start, end, type, minutes, avgHr, maxHr, calories, distance}]}
if (isset($_GET['exercise'])) {
	$n = max(1, min(60, (int) $_GET['exercise']));
	[$points, $error] = all_points('dataTypes/exercise/dataPoints?pageSize=100&filter=' . rawurlencode('exercise.interval.civil_start_time >= "' . date('Y-m-d', strtotime("-$n days")) . '"'));
	$out = [];
	foreach ($points as $p) {
		$e = $p['exercise'] ?? [];
		$i = $e['interval'] ?? [];
		if (empty($i['startTime'])) continue;
		$nums = numbers($e);
		$type = $e['exerciseType'] ?? $e['activityType'] ?? $e['type'] ?? ($e['displayName'] ?? 'Workout');
		$out[] = [
			'start' => $i['startTime'], 'end' => $i['endTime'] ?? $i['startTime'],
			'type' => is_string($type) ? $type : 'Workout',
			'minutes' => (int) round((strtotime($i['endTime'] ?? $i['startTime']) - strtotime($i['startTime'])) / 60),
			'avgHr' => pick($nums, ['/averageHeartRate|avgHeartRate|heartRate.*(avg|average)/i']),
			'maxHr' => pick($nums, ['/maxHeartRate|heartRate.*max/i']),
			'calories' => pick($nums, ['/calor|kcal|energy/i']),
			'distance' => pick($nums, ['/distance|meters|millimeters/i']),
		];
	}
	reply(['exercises' => $out, 'error' => $error]);
}

// One day minute by minute: heart rate and steps rolled up by Google into 60-second windows, oxygen during the
// night, and irregular rhythm alerts. Minutes count from local midnight; the night before is included (negative).
//   GET health.php?intraday=2026-11-01  ->  {"date", "hr": {minute: bpm}, "steps": {minute: n}, "spo2": {minute: %}, "irn": [...]}
if (isset($_GET['intraday'])) {
	$date = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['intraday']) ? $_GET['intraday'] : $today;
	$name = 'intraday-' . $date;
	$done = $date < date('Y-m-d', strtotime('-1 day'));
	if ($done && ($cached = load($name, null))) reply($cached);
	$midnight = strtotime("$date 00:00");
	$from = $midnight - 6 * 3600;
	$to = min(time(), $midnight + 86400);
	$iso = fn($t) => gmdate('Y-m-d\TH:i:s\Z', $t);
	$out = ['date' => $date, 'hr' => (object) [], 'steps' => (object) [], 'spo2' => (object) [], 'irn' => [], 'errors' => []];
	foreach (['heart-rate' => ['hr', ['/avg|average|mean/i', '/./']], 'steps' => ['steps', ['/count|sum/i', '/./']]] as $type => [$field, $patterns]) {
		[$status, $json] = api('POST', "dataTypes/$type/dataPoints:rollUp", ['range' => ['startTime' => $iso($from), 'endTime' => $iso($to)], 'windowSize' => '60s', 'pageSize' => 10000]);
		if ($status !== 200) { $out['errors'][$type] = $json['error']['message'] ?? "HTTP $status"; continue; }
		$series = [];
		foreach ($json['rollupDataPoints'] ?? [] as $p) {
			$t = strtotime($p['startTime'] ?? '');
			unset($p['startTime'], $p['endTime']);
			$v = pick(numbers($p), $patterns);
			if ($t && $v !== null && $v > 0) $series[(string) intdiv($t - $midnight, 60)] = round($v, 1);
		}
		$out[$field] = (object) $series;
	}
	[$points, $error] = all_points('dataTypes/oxygen-saturation/dataPoints?pageSize=1000&filter=' . rawurlencode('oxygen_saturation.sample_time.physical_time >= "' . $iso($from) . '" AND oxygen_saturation.sample_time.physical_time < "' . $iso($to) . '"'));
	if ($error) $out['errors']['oxygen-saturation'] = $error;
	$spo2 = [];
	foreach ($points as $p) {
		$time = null;
		array_walk_recursive($p, function ($v, $k) use (&$time) { if ($time === null && is_string($v) && preg_match('/time/i', (string) $k) && strtotime($v)) $time = strtotime($v); });
		unset($p['dataSource'], $p['dataPointName']);
		$v = pick(numbers($p), ['/percent|percentage|value/i', '/./']);
		if ($time && $v) $spo2[(string) intdiv($time - $midnight, 60)] = round($v, 1);
	}
	$out['spo2'] = (object) $spo2;
	[$points, $error] = all_points('dataTypes/irregular-rhythm-notification/dataPoints?pageSize=50');
	if ($error) $out['errors']['irregular-rhythm-notification'] = $error;
	foreach ($points as $p) {
		$time = null;
		array_walk_recursive($p, function ($v, $k) use (&$time) { if ($time === null && is_string($v) && preg_match('/startTime|time/i', (string) $k) && strtotime($v)) $time = $v; });
		if ($time) $out['irn'][] = $time;
	}
	$out['errors'] = (object) $out['errors'];
	if ($done) save($name, $out);
	reply($out);
}

$cache = isset($_GET['reset']) ? [] : load('health'); // reset=1 refetches every day
$from = date('Y-m-d', strtotime("-" . ($days - 1) . " days"));
// Fetch from the oldest missing day, but never less than the last 3 days
$fetch = date('Y-m-d', strtotime('-3 days'));
for ($d = $from; $d < $fetch; $d = date('Y-m-d', strtotime("$d +1 day"))) {
	if (!isset($cache[$d])) { $fetch = $d; break; }
}
$errors = [];

if ($fetch <= $today) {
	$fresh = [];
	for ($d = $fetch; $d <= $today; $d = date('Y-m-d', strtotime("$d +1 day"))) $fresh[$d] = ['date' => $d];
	$since = gmdate('Y-m-d\TH:i:s\Z', strtotime("$fetch -1 day"));

	// Sleep: the main sleep belongs to the day it ended; naps are listed with it
	[$points, $error] = all_points('dataTypes/sleep/dataPoints:reconcile?pageSize=25&filter=' . rawurlencode("sleep.interval.end_time >= \"$since\""));
	if ($error) $errors['sleep'] = $error;
	foreach ($points as $point) {
		$s = $point['sleep'] ?? [];
		$i = $s['interval'] ?? [];
		if (empty($i['endTime'])) continue;
		$date = local_date($i['endTime'], $i['endUtcOffset'] ?? 0);
		if (!isset($fresh[$date])) continue;
		$summary = $s['summary'] ?? [];
		$stages = [];
		foreach ($summary['stagesSummary'] ?? [] as $stage) $stages[strtolower($stage['type'] ?? '')] = (int) ($stage['minutes'] ?? 0);
		$start = strtotime($i['startTime']);
		$timeline = [];
		foreach ($s['stages'] ?? [] as $stage) {
			$timeline[] = [strtolower($stage['type'] ?? ''), (int) ((strtotime($stage['startTime']) - $start) / 60), (int) ((strtotime($stage['endTime']) - $start) / 60)];
		}
		$record = [
			'start' => $i['startTime'], 'end' => $i['endTime'], 'offset' => (int) ($i['endUtcOffset'] ?? 0),
			'asleep' => (int) ($summary['minutesAsleep'] ?? 0), 'awake' => (int) ($summary['minutesAwake'] ?? 0),
			'inBed' => (int) ($summary['minutesInSleepPeriod'] ?? 0), 'toFallAsleep' => (int) ($summary['minutesToFallAsleep'] ?? 0),
			'stages' => $stages, 'timeline' => $timeline,
		];
		$main = !empty($s['metadata']['mainSleep']);
		if ($main && (empty($fresh[$date]['sleep']) || $record['asleep'] > $fresh[$date]['sleep']['asleep'])) $fresh[$date]['sleep'] = $record;
		elseif (!$main) $fresh[$date]['naps'][] = ['start' => $record['start'], 'end' => $record['end'], 'asleep' => $record['asleep']];
	}

	// Daily totals rolled up by Google, in windows of up to 14 or 90 days
	$rollups = [
		'steps' => ['steps', 90, ['/countSum|count_sum/i', '/./']],
		'active-zone-minutes' => ['azm', 90, ['/sum/i', '/./']],
		'total-calories' => ['calories', 14, ['/kcalSum|kcal_sum|sum/i', '/./']],
	];
	foreach ($rollups as $type => [$field, $window, $patterns]) {
		for ($start = $fetch; $start <= $today; $start = date('Y-m-d', strtotime("$start +$window days"))) {
			$end = min(date('Y-m-d', strtotime("$start +$window days")), date('Y-m-d', strtotime("$today +1 day")));
			[$status, $json] = api('POST', "dataTypes/$type/dataPoints:dailyRollUp", ['range' => ['start' => civil($start), 'end' => civil($end)], 'windowSizeDays' => 1, 'pageSize' => $window]);
			if ($status !== 200) { $errors[$type] = $json['error']['message'] ?? "HTTP $status"; break; }
			foreach ($json['rollupDataPoints'] ?? [] as $point) {
				$date = civil_date($point['civilStartTime'] ?? null);
				if (!$date || !isset($fresh[$date])) continue;
				unset($point['civilStartTime'], $point['civilEndTime']);
				$value = pick(numbers($point), $patterns);
				if ($value !== null) $fresh[$date][$field] = round($value);
			}
		}
	}

	// Once-a-day values
	$daily = [
		'daily-resting-heart-rate' => ['rhr', ['/beatsPerMinute|bpm/i', '/./']],
		'daily-heart-rate-variability' => ['hrv', ['/average|rmssd|milli/i', '/./']],
		'daily-oxygen-saturation' => ['spo2', ['/average|mean|percent/i', '/./']],
		'daily-respiratory-rate' => ['breathing', ['/breathsPerMinute|average|mean/i', '/./']],
		'daily-sleep-temperature-derivations' => ['temp', ['/relative|deviation|delta|nightly/i', '/./']],
		'daily-vo2-max' => ['vo2', ['/vo2/i', '/./']],
	];
	foreach ($daily as $type => [$field, $patterns]) {
		$camel = lcfirst(str_replace(' ', '', ucwords(str_replace('-', ' ', $type))));
		// Daily types refuse a date filter: they come newest first, so page back until we pass $fetch
		$points = [];
		$token = '';
		for ($page = 0; $page < 10; $page++) {
			[$status, $json] = api('GET', "dataTypes/$type/dataPoints?pageSize=50" . ($token ? '&pageToken=' . rawurlencode($token) : ''));
			if ($status !== 200) { $errors[$type] = $json['error']['message'] ?? "HTTP $status"; break; }
			$batch = $json['dataPoints'] ?? [];
			$points = array_merge($points, $batch);
			$oldest = $batch ? find_date(end($batch)) : null;
			$token = $json['nextPageToken'] ?? '';
			if (!$token || !$oldest || $oldest < $fetch) break;
		}
		foreach ($points as $point) {
			$date = find_date($point);
			if (!$date || !isset($fresh[$date])) continue;
			unset($point['dataSource'], $point['dataPointName']);
			$t = $point['dailySleepTemperatureDerivations'] ?? null;
			if ($t && isset($t['nightlyTemperatureCelsius'], $t['baselineTemperatureCelsius'])) { $fresh[$date][$field] = round($t['nightlyTemperatureCelsius'] - $t['baselineTemperatureCelsius'], 2); continue; }
			$value = pick(numbers($point), $patterns);
			if ($value !== null) $fresh[$date][$field] = round($value, 1);
		}
	}

	foreach ($fresh as $date => $record) $cache[$date] = $record + ['fetched' => time()];
	// Keep a year at most
	ksort($cache);
	$cache = array_slice($cache, -400, null, true);
	save('health', $cache);
}

[$status, $json] = api('GET', 'pairedDevices?pageSize=10');
$device = null;
foreach ($json['pairedDevices'] ?? [] as $d) {
	$device = ['name' => $d['deviceVersion'] ?? 'Tracker', 'battery' => $d['batteryLevel'] ?? null, 'batteryStatus' => $d['batteryStatus'] ?? null, 'lastSync' => $d['lastSyncTime'] ?? null];
	break;
}

$out = [];
for ($d = $from; $d <= $today; $d = date('Y-m-d', strtotime("$d +1 day"))) {
	if (isset($cache[$d])) { $row = $cache[$d]; unset($row['fetched']); $out[] = $row; }
}
reply(['device' => $device, 'days' => $out, 'errors' => (object) $errors, 'google' => ['connected' => load('google')['connected'] ?? null]]);
