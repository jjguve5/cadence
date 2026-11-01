<?php
// Google access tokens from the stored refresh token, shared by health.php and calendar.php. The Health API refuses
// a token that also carries other scopes (calendar), so each API gets its own token, narrowed to its scopes when
// refreshing.
const HEALTH_SCOPES = [
	'https://www.googleapis.com/auth/googlehealth.settings.readonly',
	'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
	'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
	'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
	'https://www.googleapis.com/auth/googlehealth.profile.readonly',
	'https://www.googleapis.com/auth/googlehealth.irn.readonly',
];
const CALENDAR_SCOPES = ['https://www.googleapis.com/auth/calendar.readonly'];

function access_token($scopes = HEALTH_SCOPES) {
	$google = load('google');
	if (empty($google['refresh_token'])) fail(409, 'google not connected', ['reconnect' => true]);
	$granted = explode(' ', $google['scope'] ?? '');
	$wanted = array_values(array_intersect($scopes, $granted)) ?: $scopes;
	$key = md5(implode(' ', $wanted));
	$cached = $google['tokens'][$key] ?? null;
	if ($cached && $cached['expires'] > time()) return $cached['token'];
	$config = config();
	[$status, $token] = http('POST', 'https://oauth2.googleapis.com/token', ['Content-Type: application/x-www-form-urlencoded'], http_build_query([
		'client_id' => $config['google_client_id'],
		'client_secret' => $config['google_client_secret'],
		'refresh_token' => $google['refresh_token'],
		'grant_type' => 'refresh_token',
		'scope' => implode(' ', $wanted),
	]));
	if ($status !== 200 || empty($token['access_token'])) fail(409, 'google sign-in expired', ['reconnect' => true, 'detail' => $token['error_description'] ?? $token['error'] ?? null]);
	$google['tokens'][$key] = ['token' => $token['access_token'], 'expires' => time() + (int) ($token['expires_in'] ?? 3600) - 60];
	save('google', $google);
	return $token['access_token'];
}
