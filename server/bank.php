<?php
// Bank sync through Enable Banking (free for personal use). Set it up once:
//   1. Create an application at enablebanking.com (restricted, for your own accounts) and download its private key.
//   2. Put the key in data/enablebanking.pem and the application id in config.php as 'enable_app_id'.
//   3. Add <this folder>/bank.php as its redirect URL, then connect a bank from the app.
//   GET bank.php?token=..&bank=<name>   -> to the bank to consent (about 180 days)
//   GET bank.php?pull=1                  -> new transactions become "tx" records for the app
//   GET bank.php?banks=1                 -> the Portuguese banks available
//   GET bank.php                         -> connected banks and their consent dates
require __DIR__ . '/lib.php';
config();
session_set_cookie_params(['secure' => true, 'httponly' => true, 'samesite' => 'Lax']);
session_start();
const EB = 'https://api.enablebanking.com';

function b64url($s) { return rtrim(strtr(base64_encode($s), '+/', '-_'), '='); }

function jwt() {
	$config = config();
	$key = @file_get_contents(__DIR__ . '/data/enablebanking.pem');
	if (empty($config['enable_app_id']) || !$key) fail(409, 'bank sync not set up', ['setup' => true]);
	$header = b64url(json_encode(['typ' => 'JWT', 'alg' => 'RS256', 'kid' => $config['enable_app_id']]));
	$payload = b64url(json_encode(['iss' => 'enablebanking.com', 'aud' => 'api.enablebanking.com', 'iat' => time(), 'exp' => time() + 3600]));
	openssl_sign("$header.$payload", $signature, $key, OPENSSL_ALGO_SHA256);
	return "$header.$payload." . b64url($signature);
}

function eb($method, $path, $body = null) {
	return http($method, EB . $path, ['Authorization: Bearer ' . jwt(), 'Content-Type: application/json'], $body === null ? null : json_encode($body));
}

if (isset($_GET['code'])) {
	if (!hash_equals($_SESSION['bank_state'] ?? '', $_GET['state'] ?? '')) exit('Start again from the app.');
	person($_SESSION['bank_person'] ?? null);
	[$status, $session] = eb('POST', '/sessions', ['code' => $_GET['code']]);
	if ($status !== 200) exit('The bank did not confirm (' . $status . ').');
	$banks = load('banks');
	$banks[$session['session_id']] = [
		'accounts' => array_map(fn($a) => $a['uid'], $session['accounts'] ?? []),
		'bank' => $_SESSION['bank_name'] ?? '',
		'valid' => $session['access']['valid_until'] ?? null,
		'since' => date('Y-m-d', strtotime('-90 days')),
	];
	save('banks', $banks);
	header('Location: cadence://bank?ok=1');
	exit;
}

require_token();

if (isset($_GET['banks'])) {
	[$status, $json] = eb('GET', '/aspsps?country=PT');
	reply(['banks' => array_map(fn($a) => $a['name'], $json['aspsps'] ?? [])]);
}

if (isset($_GET['bank'])) {
	$_SESSION['bank_state'] = bin2hex(random_bytes(16));
	$_SESSION['bank_person'] = person();
	$_SESSION['bank_name'] = $_GET['bank'];
	[$status, $json] = eb('POST', '/auth', [
		'access' => ['valid_until' => date('c', strtotime('+179 days'))],
		'aspsp' => ['name' => $_GET['bank'], 'country' => 'PT'],
		'state' => $_SESSION['bank_state'],
		'redirect_url' => self_url('bank.php'),
		'psu_type' => 'personal',
	]);
	if ($status !== 200 || empty($json['url'])) fail(502, $json['message'] ?? "auth $status");
	header('Location: ' . $json['url']);
	exit;
}

if (isset($_GET['pull'])) {
	$banks = load('banks');
	$records = [];
	$report = [];
	foreach ($banks as $sid => $b) {
		foreach ($b['accounts'] as $uid) {
			$path = '/accounts/' . rawurlencode($uid) . '/transactions?date_from=' . $b['since'];
			for ($page = 0; $page < 10; $page++) {
				[$status, $json] = eb('GET', $path);
				if ($status !== 200) { $report[$b['bank']] = $json['message'] ?? "HTTP $status"; break; }
				foreach ($json['transactions'] ?? [] as $t) {
					$amount = (float) ($t['transaction_amount']['amount'] ?? 0);
					if (($t['credit_debit_indicator'] ?? '') === 'DBIT') $amount = -abs($amount);
					$id = 'bank-' . substr(md5($uid . ($t['entry_reference'] ?? $t['transaction_id'] ?? json_encode($t))), 0, 16);
					$name = $t['creditor']['name'] ?? $t['debtor']['name'] ?? trim(implode(' ', (array) ($t['remittance_information'] ?? [])));
					$records[] = ['tx', $id, [
						'id' => $id, 'date' => $t['booking_date'] ?? $t['value_date'] ?? date('Y-m-d'), 'minute' => 720, 'amount' => $amount,
						'merchant' => mb_substr($name ?: 'Transaction', 0, 80), 'account' => $b['bank'], 'source' => 'bank', 'reviewed' => false,
					]];
				}
				$key = $json['continuation_key'] ?? null;
				if (!$key) break;
				$path = '/accounts/' . rawurlencode($uid) . '/transactions?continuation_key=' . rawurlencode($key);
			}
		}
		$banks[$sid]['since'] = date('Y-m-d', strtotime('-5 days'));
		$report[$b['bank']] = $report[$b['bank']] ?? 'ok, consent until ' . substr((string) $b['valid'], 0, 10);
	}
	save('banks', $banks);
	reply(['added' => store_put($records), 'banks' => $report]);
}

reply(['banks' => array_values(array_map(fn($b) => ['bank' => $b['bank'], 'valid' => $b['valid']], load('banks')))]);
