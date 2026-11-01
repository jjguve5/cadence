<?php
// A fresh Google access token from the stored refresh token, shared by health.php and calendar.php.
function access_token() {
	$google = load('google');
	if (empty($google['refresh_token'])) fail(409, 'google not connected', ['reconnect' => true]);
	if (!empty($google['access_token']) && ($google['expires'] ?? 0) > time()) return $google['access_token'];
	$config = config();
	[$status, $token] = http('POST', 'https://oauth2.googleapis.com/token', ['Content-Type: application/x-www-form-urlencoded'], http_build_query([
		'client_id' => $config['google_client_id'],
		'client_secret' => $config['google_client_secret'],
		'refresh_token' => $google['refresh_token'],
		'grant_type' => 'refresh_token',
	]));
	if ($status !== 200 || empty($token['access_token'])) fail(409, 'google sign-in expired', ['reconnect' => true]);
	$google['access_token'] = $token['access_token'];
	$google['expires'] = time() + (int) ($token['expires_in'] ?? 3600) - 60;
	save('google', $google);
	return $google['access_token'];
}
