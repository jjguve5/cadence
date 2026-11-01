<?php
// Instant Apple Pay entries: a Shortcuts automation ("When I tap any Wallet card") posts the amount and merchant
// the moment you pay. The bank transaction confirms it later.
//   POST {"amount": "12,40 €", "merchant": "Pingo Doce", "card": "..."}  with header X-Cadence-Token
require __DIR__ . '/lib.php';
require_token();
$body = json_decode(file_get_contents('php://input', false, null, 0, 20000), true);
if (!is_array($body)) $body = $_POST;
$raw = (string) ($body['amount'] ?? '');
// "12,40 €", "€12.40", "1.234,56"
$clean = preg_replace('/[^0-9,.\-]/', '', $raw);
if (preg_match('/,\d{1,2}$/', $clean)) $clean = str_replace(['.', ','], ['', '.'], $clean);
else $clean = str_replace(',', '', $clean);
$amount = abs((float) $clean);
if ($amount <= 0) fail(400, 'no amount');
$now = time();
$id = 'pay-' . $now . '-' . substr(md5($raw . ($body['merchant'] ?? '')), 0, 6);
store_put([['tx', $id, [
	'id' => $id,
	'date' => date('Y-m-d', $now),
	'minute' => (int) date('G', $now) * 60 + (int) date('i', $now),
	'amount' => -$amount,
	'merchant' => mb_substr(trim((string) ($body['merchant'] ?? 'Apple Pay')), 0, 80),
	'account' => mb_substr((string) ($body['card'] ?? 'Apple Pay'), 0, 40),
	'source' => 'applepay',
	'reviewed' => false,
]]]);
reply(['ok' => true, 'id' => $id]);
