<?php
// Connects Google Health once: the app opens google.php?token=..., Google asks for consent, and the refresh token
// is kept on this server (data/google.php) so health.php can read the Fitbit data. The Google app stays in testing
// mode, so Google expires the refresh token after 7 days and the app asks to connect again.
require __DIR__ . '/lib.php';
config();
session_set_cookie_params(['secure' => true, 'httponly' => true, 'samesite' => 'Lax']);
session_start();

const SCOPES = [
	'https://www.googleapis.com/auth/googlehealth.settings.readonly',
	'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
	'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
	'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
	'https://www.googleapis.com/auth/googlehealth.profile.readonly',
	'https://www.googleapis.com/auth/googlehealth.irn.readonly',
];

function page($title, $text, $link = null) {
	header('Content-Type: text/html; charset=utf-8');
	$button = $link ? '<p><a href="' . htmlspecialchars($link) . '">Back to Cadence</a></p>' : '';
	echo '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Cadence</title>'
		. '<style>body{font:17px/1.5 system-ui;margin:0;padding:40px 24px;background:#07090e;color:#eef}a{display:inline-block;margin-top:12px;padding:12px 20px;border-radius:12px;background:#34e0b4;color:#032;font-weight:600;text-decoration:none}</style>'
		. '<h1>' . htmlspecialchars($title) . '</h1><p>' . htmlspecialchars($text) . '</p>' . $button;
	exit;
}

$config = config();
$redirect = self_url('google.php');

if (isset($_GET['error'])) page('Not connected', 'Google said: ' . $_GET['error'], 'cadence://google?ok=0');

if (isset($_GET['code'])) {
	if (!hash_equals($_SESSION['state'] ?? '', $_GET['state'] ?? '')) page('Start again', 'The sign-in expired. Open it from the app again.');
	[$status, $token] = http('POST', 'https://oauth2.googleapis.com/token', ['Content-Type: application/x-www-form-urlencoded'], http_build_query([
		'code' => $_GET['code'],
		'client_id' => $config['google_client_id'],
		'client_secret' => $config['google_client_secret'],
		'redirect_uri' => $redirect,
		'grant_type' => 'authorization_code',
	]));
	if ($status !== 200 || empty($token['refresh_token'])) page('Not connected', 'Google did not return a refresh token (' . $status . ').', 'cadence://google?ok=0');
	save('google', [
		'refresh_token' => $token['refresh_token'],
		'access_token' => $token['access_token'],
		'expires' => time() + (int) ($token['expires_in'] ?? 3600) - 60,
		'scope' => $token['scope'] ?? '',
		'connected' => time(),
	]);
	page('Connected', 'Cadence can read your Fitbit data now.', 'cadence://google?ok=1');
}

require_token();
$_SESSION['state'] = bin2hex(random_bytes(16));
header('Location: https://accounts.google.com/o/oauth2/v2/auth?' . http_build_query([
	'client_id' => $config['google_client_id'],
	'redirect_uri' => $redirect,
	'response_type' => 'code',
	'scope' => implode(' ', SCOPES),
	'state' => $_SESSION['state'],
	'access_type' => 'offline',
	'include_granted_scopes' => 'true',
	'prompt' => 'select_account consent', // the Fitbit account may not be the default one
]));
