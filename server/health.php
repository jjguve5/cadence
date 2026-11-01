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
	$filter = str_starts_with($type, 'daily-') ? "$camel.date >= \"$from\"" : "$camel.interval.start_time >= \"" . gmdate('Y-m-d\TH:i:s\Z', strtotime('-1 day')) . '"';
	reply(api('GET', "dataTypes/$type/dataPoints?pageSize=5&filter=" . rawurlencode($filter))[1]);
}

$cache = load('health');
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
		[$points, $error] = all_points("dataTypes/$type/dataPoints?pageSize=100&filter=" . rawurlencode("$camel.date >= \"$fetch\""));
		if ($error) { $errors[$type] = $error; continue; }
		foreach ($points as $point) {
			$date = find_date($point);
			if (!$date || !isset($fresh[$date])) continue;
			unset($point['dataSource'], $point['dataPointName']);
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
