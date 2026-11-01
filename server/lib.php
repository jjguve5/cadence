<?php
// Shared by every endpoint: config, the app token check, guarded storage files and HTTP calls.
// Every data file starts with a PHP guard that exits before the JSON, so none can be downloaded even where
// .htaccess is ignored.

const GUARD = "<?php http_response_code(404); exit; ?>\n";

function config() {
	static $config = null;
	if ($config === null) {
		$config = @include __DIR__ . '/config.php';
		if (!is_array($config) || empty($config['token'])) fail(500, 'config.php missing');
		date_default_timezone_set($config['timezone'] ?? 'Europe/Lisbon');
	}
	return $config;
}

function fail($code, $message, $extra = []) {
	http_response_code($code);
	header('Content-Type: application/json; charset=utf-8');
	echo json_encode(['error' => $message] + $extra);
	exit;
}

function reply($data) {
	header('Content-Type: application/json; charset=utf-8');
	header('Cache-Control: no-store');
	echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	exit;
}

// The app sends "Authorization: Bearer <token>" and X-Cadence-Token; the browser pages pass ?token=
function require_token() {
	$sent = '';
	$header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
	if (stripos($header, 'Bearer ') === 0) $sent = substr($header, 7);
	if ($sent === '') $sent = $_SERVER['HTTP_X_CADENCE_TOKEN'] ?? ''; // some hosts drop Authorization
	if ($sent === '') $sent = $_GET['token'] ?? '';
	if (!is_string($sent) || !hash_equals(config()['token'], $sent)) fail(403, 'bad token');
}

function data_path($name) {
	$dir = __DIR__ . '/data';
	if (!is_dir($dir)) mkdir($dir, 0700, true);
	return "$dir/$name.php";
}

function load($name, $default = []) {
	$text = @file_get_contents(data_path($name));
	if ($text === false) return $default;
	$value = json_decode(substr($text, strlen(GUARD)), true);
	return is_array($value) ? $value : $default;
}

function save($name, $value) {
	file_put_contents(data_path($name), GUARD . json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), LOCK_EX);
}

function http($method, $url, $headers = [], $body = null) {
	$ch = curl_init($url);
	curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_CUSTOMREQUEST => $method, CURLOPT_HTTPHEADER => $headers, CURLOPT_TIMEOUT => 40]);
	if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
	$text = curl_exec($ch);
	$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
	$error = curl_error($ch);
	curl_close($ch);
	if ($text === false) return [0, ['error' => ['message' => $error]]];
	return [$status, json_decode($text, true) ?? ['raw' => $text]];
}

function self_url($file) {
	return 'https://' . $_SERVER['HTTP_HOST'] . rtrim(dirname($_SERVER['SCRIPT_NAME']), '/') . '/' . $file;
}

// Adds records to the sync store from the server side (Apple Pay entries, bank transactions), so they reach the
// app like any other change. Records the app already has are never overwritten, unless $replace($old) says so.
function store_put($records, $replace = null) {
	$handle = fopen(data_path('store'), 'c+');
	if (!$handle) fail(500, 'cannot open the store');
	flock($handle, LOCK_EX);
	$store = json_decode(substr(stream_get_contents($handle), strlen(GUARD)), true);
	if (!is_array($store)) $store = ['rev' => 0, 'records' => []];
	$added = 0;
	foreach ($records as [$type, $id, $data]) {
		$old = $store['records']["$type:$id"] ?? null;
		if ($old && !(empty($old['deleted']) && $replace && $replace($old))) continue;
		$store['rev']++;
		$store['records']["$type:$id"] = ['type' => $type, 'id' => $id, 'rev' => $store['rev'], 'updated' => (int) (microtime(true) * 1000), 'deleted' => false, 'data' => $data];
		$added++;
	}
	if ($added) {
		ftruncate($handle, 0);
		rewind($handle);
		fwrite($handle, GUARD . json_encode($store, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
		fflush($handle);
	}
	flock($handle, LOCK_UN);
	fclose($handle);
	return $added;
}
