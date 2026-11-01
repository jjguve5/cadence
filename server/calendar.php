<?php
// Google Calendar events for the plan, read-only: every calendar you have selected, as fixed blocks.
//   GET calendar.php?from=2026-11-01&days=2  ->  {"events": [{id, title, start, end, allDay, calendar, color}]}
require __DIR__ . '/lib.php';
require __DIR__ . '/google_token.php';
require_token();
$from = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['from'] ?? '') ? $_GET['from'] : date('Y-m-d');
$days = max(1, min(14, (int) ($_GET['days'] ?? 2)));
$min = date('c', strtotime($from));
$max = date('c', strtotime("$from +$days days"));
$headers = ['Authorization: Bearer ' . access_token(CALENDAR_SCOPES)];
[$status, $list] = http('GET', 'https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader', $headers);
if ($status === 403 || $status === 401) {
	$granted = load('google')['scope'] ?? '';
	$reason = (strpos($granted, 'calendar') !== false) ? 'enable the Google Calendar API in your Cloud project' : 'connect Google again so it can include the calendar';
	fail(403, 'calendar not allowed: ' . $reason, ['reconnect' => !(strpos($granted, 'calendar') !== false), 'google' => $list['error']['message'] ?? null]);
}
if ($status !== 200) fail(502, $list['error']['message'] ?? "calendar list $status");
$events = [];
foreach ($list['items'] ?? [] as $cal) {
	if (isset($cal['selected']) && !$cal['selected']) continue;
	$url = 'https://www.googleapis.com/calendar/v3/calendars/' . rawurlencode($cal['id']) . '/events?' . http_build_query([
		'timeMin' => $min, 'timeMax' => $max, 'singleEvents' => 'true', 'orderBy' => 'startTime', 'maxResults' => 250,
	]);
	[$s, $json] = http('GET', $url, $headers);
	if ($s !== 200) continue;
	foreach ($json['items'] ?? [] as $e) {
		if (($e['status'] ?? '') === 'cancelled') continue;
		$mine = null;
		foreach ($e['attendees'] ?? [] as $a) if (!empty($a['self'])) $mine = $a['responseStatus'] ?? null;
		if ($mine === 'declined') continue;
		$allDay = isset($e['start']['date']);
		$events[] = [
			'id' => $e['id'],
			'title' => $e['summary'] ?? '(busy)',
			'start' => $allDay ? $e['start']['date'] : date('c', strtotime($e['start']['dateTime'])),
			'end' => $allDay ? $e['end']['date'] : date('c', strtotime($e['end']['dateTime'])),
			'allDay' => $allDay,
			'calendar' => $cal['summaryOverride'] ?? $cal['summary'] ?? '',
			'color' => $cal['backgroundColor'] ?? null,
			'location' => $e['location'] ?? null,
		];
	}
}
usort($events, fn($a, $b) => strcmp($a['start'], $b['start']));
reply(['events' => $events]);
